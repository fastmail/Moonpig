package Moonpig::Role::Consumer;
# ABSTRACT: something that uses up money stored in a bank
use Moose::Role;

use Stick::Publisher 0.20110324;
use Stick::Publisher::Publish 0.20110324;
use Moonpig::Trait::Copy;

with(
  'Moonpig::Role::CanCancel',
  'Moonpig::Role::CanExpire',
  'Moonpig::Role::HandlesEvents',
  'Moonpig::Role::HasGuid',
  'Moonpig::Role::LedgerComponent',
  'Moonpig::Role::StubBuild',
  'Moonpig::Role::CanTransfer' => { transferer_type => "consumer" },
  'Stick::Role::PublicResource',
  'Stick::Role::PublicResource::GetSelf',
  'Stick::Role::Routable::ClassAndInstance',
  'Stick::Role::Routable::AutoInstance',
);

sub _class_subroute { return }

use MooseX::SetOnce;
use Moonpig::Types qw(Ledger Millicents MRI TimeInterval XID);
use Moonpig::Util qw(class event);

use Moonpig::Logger '$Logger';
use namespace::autoclean;

use Moonpig::Behavior::Packable;

use Moonpig::Behavior::EventHandlers;
implicit_event_handlers {
  return {
    'activated' => {
      noop => Moonpig::Events::Handler::Noop->new,
    },
    'consumer-create-replacement' => {
      create_replacement => Moonpig::Events::Handler::Method->new(
        method_name => 'create_own_replacement',
      ),
    },
    'fail-over' => {
      default => Moonpig::Events::Handler::Method->new(
        method_name => 'failover',
      ),
    },
    'terminate' => {
      default => Moonpig::Events::Handler::Method->new(
        method_name => 'handle_terminate',
      ),
    },
  };
};

has replacement => (
  is   => 'rw',
  does => 'Moonpig::Role::Consumer',
  traits    => [ qw(SetOnce) ],
  predicate => 'has_replacement',
);

# If the consumer does not yet have a replacement, it may try to
# manufacture a replacement as described by this MRI
has replacement_mri => (
  is => 'rw',
  isa => MRI,
  required => 1,
  coerce => 1,
  traits => [ qw(Copy) ],
);

# XXX this is for testing only; when we figure out replacement semantics
has is_replaceable => (
  is => 'ro',
  isa => 'Bool',
  default => 1,
  traits => [ qw(Copy) ],
);

sub create_own_replacement {
  my ($self, $event, $arg) = @_;

  my $replacement_mri = $event->payload->{mri};

  $Logger->log([ "trying to set up replacement for %s", $self->TO_JSON ]);

  if ($self->is_replaceable && ! $self->has_replacement) {
    # The replacement must be a consumer template, of course.
    my $replacement_template = $replacement_mri->construct({
      extra => { self => $self }
    });

    return unless $replacement_template;

    my $replacement = $self->ledger->add_consumer_from_template(
      $replacement_template,
      { xid => $self->xid },
    );

    $self->replacement($replacement);
    return $replacement;
  }

  return;
}

sub handle_cancel {
  my ($self, $event) = @_;
  return if $self->is_canceled;

  $self->mark_canceled;
  if ($self->has_replacement) {
    $self->replacement->expire
  } else {
    $self->replacement_mri(Moonpig::URI->nothing);
  }
  return;
}

has xid => (
  is  => 'ro',
  isa => XID,
  required => 1,
  traits => [ qw(Copy) ],
);

before expire => sub {
  my ($self) = @_;

  $self->handle_event(
    $self->has_replacement
    ? event('fail-over')
    : event('terminate')
  );
};

after BUILD => sub {
  my ($self, $arg) = @_;

  $self->become_active if delete $arg->{make_active};
};

sub is_active {
  my ($self) = @_;

  $self->ledger->_is_consumer_active($self);
}

# note that this might be called before the consumer is added to the ledger.
# So don't expect that $self->ledger->active_consumer_for_xid($self->xid)
# will return $self here. 20110610 MJD
sub become_active {
  my ($self) = @_;

  $self->ledger->mark_consumer_active__($self);

  $self->handle_event( event('activated') );
}

sub failover {
  my ($self) = @_;

  $self->ledger->failover_active_consumer__($self);
}

publish _terminate => { -http_method => 'post', -path => 'terminate' } => sub {
  my ($self) = @_;
  $self->handle_event(event('terminate'));
  return;
};

sub handle_terminate {
  my ($self, $event) = @_;

  $Logger->log([
    'terminating service: %s',
    $self->ident,
  ]);

  $self->handle_event(event('cancel'));
  $self->ledger->mark_consumer_inactive__($self);
}

# Create a copy of myself in the specified ledger; commit suicide,
# and return the copy.
# This method is called "copy_to" and not "move_to" by analogy with
# Unix "cp" (which it is like) and not "mv" (which it is not).  The
# original consumer object is not merely relinked into the new ledger;
# it is copied there.
sub copy_to {
  my ($self, $target) = @_;
  my $copy;
  Moonpig->env->storage->do_rw(
    sub {
      $copy = $target->add_consumer(
        $self->meta->name,
        $self->copy_attr_hash__
      );
      $self->copy_subcomponents_to__($target, $copy);
      { # We have to terminate service before activating service, or else the
        # same xid would be active in both ledgers at once, which is forbidden
        my $was_active = $self->is_active;
        $self->handle_event(event('terminate'));
        $copy->become_active if $was_active;
      }
    });
  return $copy;
}

# roles will decorate this method with code to move subcomponents like banks to
# the copy
sub copy_subcomponents_to__ {
  my ($self, $target, $copy) = @_;
  $copy->replacement($self->replacement->copy_to($target))
    if $self->replacement;
}

sub copy_attr_hash__ {
  my ($self) = @_;
  my %hash;
  for my $attr ($self->meta->get_all_attributes) {
    if ($attr->does("Moose::Meta::Attribute::Custom::Trait::Copy")
          && $attr->has_value($self)) {
      my $name = $attr->name;
      my $read_method = $attr->get_read_method;
      $hash{$name} = $self->$read_method();
    }
  }
  return \%hash;
}


sub template_like_this {
  my ($self) = @_;
  return {
    class => $self->meta->name,
    arg   => $self->copy_attr_hash__,
  };
}

PARTIAL_PACK {
  return { xid => $_[0]->xid };
};

1;

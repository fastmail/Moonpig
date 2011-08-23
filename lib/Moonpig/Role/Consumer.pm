package Moonpig::Role::Consumer;
# ABSTRACT: something that uses up money stored in a bank
use Moose::Role;

use Stick::Publisher 0.20110324;
use Stick::Publisher::Publish 0.20110324;
use Stick::Util qw(true false);
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
use Moonpig::Types qw(Ledger Millicents TimeInterval XID);
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
        method_name => 'build_and_install_replacement',
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

has replacement_XXX => (
  is  => 'rw',
  isa => 'ArrayRef',
  # isa => 'ReplacementXXX', # XXX -- rjbs, 2011-08-22
  required => 1,
  traits   => [ qw(Array Copy) ],
  handles  => {
    replacement_XXX_parts => 'elements',
  },
);

sub build_and_install_replacement {
  my ($self) = @_;

  # Shouldn't this be fatal? -- rjbs, 2011-08-22
  return if $self->has_replacement;

  $Logger->log([ "trying to set up replacement for %s", $self->TO_JSON ]);

  my $replacement_template = $self->_replacement_template;

  # i.e., it's okay if we return undef from _replacement_template; that's how
  # "nothing" will work
  return unless $replacement_template;

  my $replacement = $self->ledger->add_consumer_from_template(
    $replacement_template,
    { xid => $self->xid },
  );

  $self->replacement($replacement);
  return $replacement;
}

sub _replacement_template {
  my ($self) = @_;

  my ($method, $uri, $arg) = $self->replacement_XXX_parts;

  my @parts = split m{/}, $uri;

  my $wrapped_method;

  if ($parts[0] eq '') {
    # /foo/bar -> [ '', 'foo', 'bar' ]
    shift @parts;
    $wrapped_method = Moonpig->env->route(\@parts);
  } else {
    $wrapped_method = $self->route(\@parts);
  }

  my $result;

  if ($method eq 'get') {
    $result = $wrapped_method->resource_get;
  } elsif ($method eq 'post' or $method eq 'put') {
    my $call = "resource_$method";
    $result = $wrapped_method->$call($arg);
  } else {
    Moonpig::X->throw("illegal replacement XXX method");
  }

  return $result;
}

sub handle_cancel {
  my ($self, $event) = @_;
  return if $self->is_canceled;

  $self->mark_canceled;
  if ($self->has_replacement) {
    $self->replacement->expire
  } else {
    $self->replacement_XXX([ get => '/nothing' ]);
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

  $self->ledger->_is_consumer_active($self) ? true : false;
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

publish template_like_this => {
  '-http_method' => 'get',
  '-path'        => 'template-like-this',
} => sub {
  my ($self) = @_;

  return {
    class => $self->meta->name,
    arg   => $self->copy_attr_hash__,
  };
};

PARTIAL_PACK {
  return {
    xid       => $_[0]->xid,
    is_active => $_[0]->is_active,
  };
};

1;

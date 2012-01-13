package Moonpig::Role::Consumer;
# ABSTRACT: something that uses up money
use Moose::Role;

use Carp qw(confess croak);
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

use Moose::Util::TypeConstraints qw(role_type);
use MooseX::SetOnce;
use MooseX::Types::Moose qw(ArrayRef);
use Moonpig::Types qw(Ledger Millicents Time TimeInterval XID ReplacementPlan);
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

has created_at => (
  is   => 'ro',
  isa  => Time,
  init_arg => undef,
  default  => sub { Moonpig->env->now },
);

has _superseded => (
  is => 'rw',
  isa => 'Bool',
  reader => 'is_superseded',
  default => 0,
  init_arg => undef,
);

sub mark_superseded {
  my ($self) = @_;
  return if $self->is_superseded;
  $self->_superseded(1);
  for my $repl (@{$self->_replacement_history}) {
    $repl->mark_superseded if $repl;
  }
}

has _replacement_history => (
  is   => 'ro',
  isa => ArrayRef [ role_type('Moonpig::Role::Consumer') ],
  default => sub { [] },
);

# Convert (replacement => $foo) to (replacement_history => [$foo])
around BUILDARGS => sub {
  my $orig  = shift;
  my $class = shift;
  my $args = @_ == 1 ? $_[0] : { @_ };
  if (my $replacement = delete $args->{replacement}) {
    $args->{_replacement_history} = [ $replacement ];
  }
  return $class->$orig($args);
};

# List of this consumer's replacement, replacement's replacement, etc.
sub replacement_chain {
  my ($self) = @_;
  return $self->has_replacement
    ? ($self->replacement, $self->replacement->replacement_chain) : ();
}

# Does this consumer, or any consumer in its replacement chain,
# have funds?  If so, the funds will be lost if the consumer is superseded
sub is_funded {
  my ($self) = @_;
  return $self->unapplied_amount > 0
    || ($self->has_replacement && $self->replacement->is_funded);
}

sub replacement {
  my ($self, $new_replacement) = @_;

  if (defined $new_replacement) {
    croak "Too late to set replacement of expired consumer $self" if $self->is_expired;
    croak "Can't set replacement on superseded consumer $self" if $self->is_superseded;
    if ($self->has_replacement) {
      croak "Can't replace funded consumer chain" if $self->replacement->is_funded;
      $self->replacement->mark_superseded;
    }

    push @{$self->_replacement_history}, $new_replacement;
    return $new_replacement;
  } else {
    return $self->_replacement_history->[-1];
  }
}

sub has_replacement {
  my ($self) = @_;
  defined($self->replacement);
}

has replacement_plan => (
  is  => 'rw',
  isa => ReplacementPlan,
  required => 1,
  traits   => [ qw(Array Copy) ],
  handles  => {
    replacement_plan_parts => 'elements',
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
    { xid => $self->xid, $self->_replacement_extra_args },
  );

  $self->replacement($replacement);
  return $replacement;
}

sub _replacement_extra_args { return () }

sub _replacement_template {
  my ($self) = @_;

  my ($method, $uri, $arg) = $self->replacement_plan_parts;

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
    $self->replacement_plan([ get => '/nothing' ]);
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
      $target->save;
      $self->copy_balance_to__($copy);
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

# "Move" my balance to a different consumer.  This will work even if
# the consumer is in a different ledger.  It works by entering a
# charge to the source consumer for its entire remaining funds, then
# creating a credit in the recipient consumer's ledger and
# transferring the credit to the recipient.
sub copy_balance_to__ {
  my ($self, $new_consumer) = @_;
  my $amount = $self->unapplied_amount;
  return if $amount == 0;

  Moonpig->env->storage->do_rw(
    sub {
      my ($ledger, $new_ledger) = ($self->ledger, $new_consumer->ledger);
      $ledger->current_journal->charge({
        desc        => sprintf("Transfer management of '%s' to ledger %s",
                               $self->xid, $new_ledger->guid),
        from        => $self,
        to          => $ledger->current_journal,
        date        => Moonpig->env->now,
        amount      => $amount,
        tags        => [ @{$self->journal_charge_tags}, "transient" ],
      });
      my $credit = $new_ledger->add_credit(
        class('Credit::Transient'),
        {
          amount               => $amount,
          source_guid          => $self->guid,
          source_ledger_guid   => $ledger->guid,
        });
      my $transient_invoice = class("Invoice")->new({
         ledger      => $new_ledger,
      });
      my $charge = $transient_invoice->add_charge(
        class('InvoiceCharge')->new({
          description => sprintf("Transfer management of '%s' from ledger %s",
                                 $self->xid, $ledger->guid),
          amount      => $amount,
          consumer    => $new_consumer,
          tags        => [ @{$new_consumer->journal_charge_tags}, "transient" ],
        }),
       );
      $new_ledger->apply_credits_to_invoice__(
        [{ credit => $credit,
           amount => $amount }],
        $transient_invoice);
      $new_ledger->save;
    });
}


# roles will decorate this method with code to move subcomponents to the copy
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

has extra_journal_charge_tags => (
  is  => 'ro',
  isa => ArrayRef,
  default => sub { [] },
  traits => [ qw(Copy) ],
);

sub journal_charge_tags {
  my ($self) = @_;
  return [ $self->xid, @{$self->extra_journal_charge_tags} ]
}

sub build_charge {
  my ($self, $args) = @_;
  return class('InvoiceCharge')->new($args);
}

has extra_invoice_charge_tags => (
  is  => 'ro',
  isa => ArrayRef,
  default => sub { [] },
  traits => [ qw(Copy) ],
);

sub invoice_charge_tags {
  my ($self) = @_;
  return [ $self->xid, @{$self->extra_invoice_charge_tags} ]
}

PARTIAL_PACK {
  return {
    xid       => $_[0]->xid,
    is_active => $_[0]->is_active,
    unapplied_amount => $_[0]->unapplied_amount,
  };
};

1;

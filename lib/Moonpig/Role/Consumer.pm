package Moonpig::Role::Consumer;
# ABSTRACT: something that uses up money stored in a bank
use Moose::Role;
with(
  'Moonpig::Role::CanExpire',
  'Moonpig::Role::HandlesEvents',
  'Moonpig::Role::HasGuid',
  'Moonpig::Role::LedgerComponent',
  'Moonpig::Role::StubBuild',
  'Moonpig::Role::CanTransfer' => { transferer_type => "consumer" },
);

use Moonpig::Behavior::EventHandlers;
implicit_event_handlers {
  return {
    'consumer-create-replacement' => {
      create_replacement => Moonpig::Events::Handler::Method->new(
        method_name => 'create_own_replacement',
      ),
    },
  };
};

use MooseX::SetOnce;
use Moonpig::Types qw(ChargePath Ledger Millicents MRI TimeInterval);
use Moonpig::Util qw(class event);

use Moonpig::Logger '$Logger';

use Moonpig::Behavior::EventHandlers;

use namespace::autoclean;

implicit_event_handlers {
  return {
    'activated' => {
      noop => Moonpig::Events::Handler::Noop->new,
    },
    'fail-over' => {
      default => Moonpig::Events::Handler::Method->new(
        method_name => 'failover',
      ),
    },
    'terminate-service' => {
      default => Moonpig::Events::Handler::Method->new(
        method_name => 'terminate_service',
      ),
    },
  };
};

has bank => (
  reader => 'bank',
  writer => '_set_bank',
  does   => 'Moonpig::Role::Bank',
  traits => [ qw(SetOnce) ],
  predicate => 'has_bank',
);

before _set_bank => sub {
  my ($self, $bank) = @_;

  unless ($self->ledger->guid eq $bank->ledger->guid) {
    confess sprintf(
      "cannot associate consumer from %s with bank from %s",
      $self->ledger->ident,
      $bank->ledger->ident,
    );
  }
};

sub unapplied_amount {
  my ($self) = @_;
  return $self->has_bank ? $self->bank->unapplied_amount : 0;
}

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
);

# XXX this is for testing only; when we figure out replacement semantics
has is_replaceable => (
  is => 'ro',
  isa => 'Bool',
  default => 1,
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

# the date is appended to this to make the cost path
# for this consumer's charges
has charge_path_prefix => (
  is => 'ro',
  isa => ChargePath,
  coerce => 1,
  required => 1,
);

# When the object has less than this long to live, it will
# start posting low-balance events to its successor, or to itself if
# it has no successor
has old_age => (
  is => 'ro',
  required => 1,
  isa => TimeInterval,
);

sub amount_in_bank {
  my ($self) = @_;
  return $self->has_bank ? $self->bank->unapplied_amount : 0;
}

has xid => (
  is  => 'ro',
  isa => 'Str',
  required => 1,
);

before expire => sub {
  my ($self) = @_;

  $self->handle_event(
    $self->has_replacement
    ? event('fail-over')
    : event('terminate-service')
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

sub become_active {
  my ($self) = @_;

  $self->ledger->mark_consumer_active__($self);

  $self->handle_event( event('activated') );
}

sub failover {
  my ($self) = @_;

  $self->ledger->failover_active_consumer__($self);
}

sub terminate_service {
  my ($self) = @_;

  $Logger->log([
    'terminating service: %s',
    $self->ident,
  ]);

  $self->ledger->mark_consumer_inactive__($self);
}

1;

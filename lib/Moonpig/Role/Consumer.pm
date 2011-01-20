package Moonpig::Role::Consumer;
# ABSTRACT: something that uses up money stored in a bank
use Moose::Role;
with(
  'Moonpig::Role::LedgerComponent',
  'Moonpig::Role::HasGuid',
  'Moonpig::Role::StubBuild',
  'Moonpig::Role::CanExpire',
);

use MooseX::SetOnce;
use Moonpig::Types qw(Ledger Millicents MRI);
use Moonpig::Util qw(class event);

use Moonpig::Logger '$Logger';

use Moonpig::Behavior::EventHandlers;

use namespace::autoclean;

implicit_event_handlers {
  return {
    'terminate-service' => {
      default => Moonpig::Events::Handler::Method->new(
        method_name => 'terminate_service',
      ),
    },
    'fail-over' => {
      default => Moonpig::Events::Handler::Method->new(
        method_name => 'failover',
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

sub amount_in_bank {
  my ($self) = @_;
  return $self->has_bank ? $self->bank->unapplied_amount : 0;
}

has service_uri => (
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

  $self->become_active if delete $arg->{service_active};
};

sub is_active {
  my ($self) = @_;

  $self->ledger->_is_consumer_active($self);
}

sub become_active {
  my ($self) = @_;

  $self->ledger->mark_consumer_active__($self);
}

sub failover {
  my ($self) = @_;

  $Logger->log("XXX: failing over");
  $self->ledger->failover_active_consumer__($self);
}

sub terminate_service {
  my ($self) = @_;

  $Logger->log([
    'terminating service: %s, %s',
    $self->charge_description,
    $self->ident,
  ]);

  $self->ledger->mark_consumer_inactive__($self);
}

1;

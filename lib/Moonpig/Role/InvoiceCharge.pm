package Moonpig::Role::InvoiceCharge;
use Moose::Role;
# ABSTRACT: a charge placed on an invoice

with(
  'Moonpig::Role::ChargeLike',
  'Moonpig::Role::ConsumerComponent',
  'Moonpig::Role::HandlesEvents',
  'Moonpig::Role::ChargeLike::RequiresPositiveAmount',
);

use namespace::autoclean;
use Moonpig::Behavior::EventHandlers;
use Moonpig::Behavior::Packable;
use Moonpig::Types qw(Time);
use MooseX::SetOnce;

has abandoned_at => (
  is => 'ro',
  isa => Time,
  predicate => 'is_abandoned',
  writer    => '__set_abandoned_at',
  traits => [ qw(SetOnce) ],
);

sub counts_toward_total { ! $_[0]->is_abandoned }
sub is_charge { 1 }

sub mark_abandoned {
  my ($self) = @_;
  Moonpig::X->throw("can't abandon an executed charge") if $self->is_executed;
  $self->__set_abandoned_at( Moonpig->env->now );
}

has executed_at => (
  is  => 'ro',
  isa => Time,
  predicate => 'is_executed',
  writer    => '__set_executed_at',
  traits    => [ qw(SetOnce) ],
);

implicit_event_handlers {
  return {
    'paid' => {
      'default' => Moonpig::Events::Handler::Noop->new,
    },
  }
};

PARTIAL_PACK {
  my ($self) = @_;

  return {
    owner_guid   => $self->owner_guid,
    executed_at  => $self->executed_at,
    abandoned_at => $self->abandoned_at,
  };
};

1;

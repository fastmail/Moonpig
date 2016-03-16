package Moonpig::Role::InvoiceCharge;
# ABSTRACT: a charge placed on an invoice

use Moose::Role;

with(
  'Moonpig::Role::LineItem',
  'Moonpig::Role::LineItem::Abandonable',
  'Moonpig::Role::LineItem::RequiresPositiveAmount',
  'Moonpig::Role::HandlesEvents',
);

use namespace::autoclean;
use Moonpig::Behavior::EventHandlers;
use Moonpig::Behavior::Packable;
use Moonpig::Types qw(Time);
use MooseX::SetOnce;

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

sub acquire_funds {
  my ($self, $credits) = @_;

  my $still_need = $self->amount;

  CREDIT: for my $credit (@$credits) {
    my $to_xfer = $credit->unapplied_amount >= $still_need
                ? $still_need
                : $credit->unapplied_amount;

    next CREDIT unless $to_xfer;

    $self->ledger->accountant->create_transfer({
      type => 'consumer_funding',
      from => $credit,
      to   => $self->owner,
      amount => $to_xfer,
    });

    $still_need -= $to_xfer;

    last CREDIT if $still_need == 0;
  }

  $self->__set_executed_at( Moonpig->env->now );
  return;
}

PARTIAL_PACK {
  my ($self) = @_;

  return {
    owner_guid   => $self->owner_guid,
    executed_at  => $self->executed_at,
  };
};

1;

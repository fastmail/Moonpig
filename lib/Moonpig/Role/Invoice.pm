package Moonpig::Role::Invoice;
# ABSTRACT: a collection of charges to be paid by the customer
use Moose::Role;

with(
  'Moonpig::Role::ChargeTreeContainer' => { charges_handle_events => 1 },
  'Moonpig::Role::LedgerComponent',
  'Moonpig::Role::HandlesEvents',
  'Moonpig::Role::HasGuid',
  'Moonpig::Role::Payable',
);

use Moonpig::Behavior::EventHandlers;

use Moonpig::CreditApplication;
use Moonpig::Util qw(event);
use Moonpig::Types qw(Credit Time);
use Moonpig::X;

use namespace::autoclean;

has created_at => (
  is   => 'ro',
  isa  => Time,
  default => sub { Moonpig->env->now },
);

sub finalize_and_send {
  my ($self) = @_;

  $self->close;

  $self->ledger->handle_event( event('send-invoice', { invoice => $self }) );
}

has paid => (
  isa => 'Bool',
  init_arg => undef,
  default  => 0,
  reader   => 'is_paid',
  traits   => [ 'Bool' ],
  handles  => {
    mark_paid => 'set',
    is_unpaid => 'not',
  },
);

implicit_event_handlers {
  return {
    'paid' => {
      redistribute => Moonpig::Events::Handler::Method->new('_pay_charges'),
    }
  };
};

sub _pay_charges {
  my ($self, $event) = @_;

  $self->charge_tree->apply_to_all_charges(sub { $_->handle_event($event) });
}

1;

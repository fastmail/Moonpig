package Moonpig::Role::InvoiceCharge::Bankable;
# ABSTRACT: a charge that, when paid, creates a bank for the paid amount
use Moose::Role;

with(
  'Moonpig::Role::InvoiceCharge',
);

use Moonpig::Behavior::EventHandlers;
use Moonpig::Util qw(class);

use namespace::autoclean;

has consumer => (
  is   => 'ro',
  does => 'Moonpig::Role::Consumer',
  required => 1,
  handles  => [ qw(ledger) ],
);

sub _bank_credit {
  my ($self, $event) = @_;

  my $bank = $self->ledger->add_bank(
    class(qw(Bank)),
    {
      amount => $self->amount,
    },
  );

  $self->consumer->_set_bank($bank);
}

implicit_event_handlers {
  return {
    'paid' => {
      'create-bank' => Moonpig::Events::Handler::Method->new('_bank_credit'),
    },
  }
};

1;

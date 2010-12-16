package Moonpig::Role::Charge::Bankable;
use Moose::Role;

with(
  'Moonpig::Role::Charge',
  'Moonpig::Role::HandlesEvents',
);

use Moonpig::Behavior::EventHandlers;

use namespace::autoclean;

has consumer => (
  is   => 'ro',
  does => 'Moonpig::Role::Consumer',
  required => 1,
  handles  => [ qw(ledger) ],
);

sub _bank_credit {
  my ($self, $event) = @_;

  my $bank = Moonpig::Bank::Basic->new({
    amount => $self->amount,
    ledger => $self->ledger,
  });

  $self->ledger->add_bank($bank);

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

package Moonpig::Role::Credit::FromPayment;
use Moose::Role;

use Moonpig::X;

use namespace::autoclean;

with(
  'Moonpig::Role::Credit',
  'Moonpig::Role::Refundable',
);

has payment => (
  is   => 'ro',
  does => 'Moonpig::Role::Payment',
  handles  => 'Moonpig::Role::Refundable',
  required => 1,
);

before issue_refund => sub {
  my ($self) = @_;

  Moonpig::X->throw("cannot refund partially applied payment")
    unless $self->unapplied_amount == $self->amount;
};

1;

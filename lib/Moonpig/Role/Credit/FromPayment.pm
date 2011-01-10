package Moonpig::Role::Credit::FromPayment;
# ABSTRACT: a credit created because a customer paid us
use Moose::Role;

use Moonpig::X;

use namespace::autoclean;

with(
  'Moonpig::Role::Credit',
  'Moonpig::Role::Refundable',
);

before issue_refund => sub {
  my ($self) = @_;

  Moonpig::X->throw("cannot refund partially applied payment")
    unless $self->unapplied_amount == $self->amount;
};

1;

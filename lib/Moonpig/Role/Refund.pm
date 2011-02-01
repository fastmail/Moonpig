package Moonpig::Role::Refund;
# ABSTRACT: a representation of a refund of credit to a customer
use Moose::Role;

with(
  'Moonpig::Role::LedgerComponent',
  'Moonpig::Role::HasGuid',
  'Moonpig::Role::Payable',
);

use List::Util qw(reduce);

use namespace::autoclean;

sub amount {
  my ($self) = @_;
  return $self->accountant->all_for_payable($self)->total;
}

1;

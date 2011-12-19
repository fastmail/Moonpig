package Moonpig::Role::Refund;
# ABSTRACT: a representation of a refund of credit to a customer
use Moose::Role;

with(
  'Moonpig::Role::LedgerComponent',
  'Moonpig::Role::HasGuid',
  'Moonpig::Role::CanTransfer' => { transferer_type => "refund" },
);

use namespace::autoclean;

sub amount {
  my ($self) = @_;
  return $self->accountant->all_for_refund($self)->total;
}

1;

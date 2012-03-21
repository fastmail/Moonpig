package Moonpig::Role::Debit;
# ABSTRACT: a representation of a loss of credit
use Moose::Role;

with(
  'Moonpig::Role::LedgerComponent',
  'Moonpig::Role::HasGuid',
  'Moonpig::Role::CanTransfer' => { transferer_type => "debit" },
);

use namespace::autoclean;

sub amount {
  my ($self) = @_;
  return $self->accountant->all_for_debit($self)->total;
}

1;

package Moonpig::Role::Debit::Refund;
# ABSTRACT: a representation of a refund of credit to a customer

use Moose::Role;

with(
  'Moonpig::Role::Debit',
);

1;

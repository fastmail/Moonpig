package Moonpig::Role::Refund;
use Moose::Role;

with(
  'Moonpig::Role::LedgerComponent',
  'Moonpig::Role::HasGuid',
  'Moonpig::Role::Payable',
);

1;

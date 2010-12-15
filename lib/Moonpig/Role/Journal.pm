package Moonpig::Role::Journal;
use Moose::Role;

with(
  'Moonpig::Role::CostTreeContainer',
  'Moonpig::Role::LedgerComponent',
);

use namespace::autoclean;

1;

package Moonpig::Role::Journal;
use Moose::Role;

with(
  'Moonpig::Role::CostTreeContainer' => { charges_handle_events => 0 },
  'Moonpig::Role::LedgerComponent',
);

use namespace::autoclean;

1;

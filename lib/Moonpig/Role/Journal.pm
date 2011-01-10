package Moonpig::Role::Journal;
# ABSTRACT: a journal of charges made by consumers against banks
use Moose::Role;

with(
  'Moonpig::Role::CostTreeContainer' => { charges_handle_events => 0 },
  'Moonpig::Role::LedgerComponent',
);

use namespace::autoclean;

1;

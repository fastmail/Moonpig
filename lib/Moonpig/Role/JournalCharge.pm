package Moonpig::Role::JournalCharge;
use Moose::Role;
with(
  'Moonpig::Role::Charge',
);

use namespace::autoclean;

sub counts_toward_total { 1 }

1;

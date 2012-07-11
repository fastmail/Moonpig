package Moonpig::Role::JournalCharge;
use Moose::Role;
# ABSTRACT: a charge placed on an journal
with(
  'Moonpig::Role::Charge',
  'Moonpig::Role::Charge::RequiresPositiveAmount',
);

use namespace::autoclean;

sub counts_toward_total { 1 }
sub is_charge { 1 }

1;

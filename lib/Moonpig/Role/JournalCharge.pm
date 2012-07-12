package Moonpig::Role::JournalCharge;
use Moose::Role;
# ABSTRACT: a charge placed on an journal
with(
  'Moonpig::Role::ChargeLike',
  'Moonpig::Role::ChargeLike::RequiresPositiveAmount',
);

use namespace::autoclean;

sub counts_toward_total { 1 }
sub is_charge { 1 }

1;

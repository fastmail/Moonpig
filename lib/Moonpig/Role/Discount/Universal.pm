package Moonpig::Role::Discount::Universal;
# ABSTRACT: a discount that applies to all charges

use Moose::Role;

with(
  'Moonpig::Role::Discount',
);

sub applies_to_charge { 1 }

1;


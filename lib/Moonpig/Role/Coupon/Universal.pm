package Moonpig::Role::Coupon::Universal;
# ABSTRACT: a coupon that applies to all charges
use Moose::Role;

with(
  'Moonpig::Role::Coupon',
);

sub applies_to_charge { 1 }

1;


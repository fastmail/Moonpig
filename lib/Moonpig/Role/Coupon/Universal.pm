package Moonpig::Role::Coupon::Universal;
# ABSTRACT: a coupon that applies to all charges
use Moose::Role;

with(
  'Moonpig::Role::Coupon',
);

sub applies_to { 1 }

1;


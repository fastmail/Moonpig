package Moonpig::Role::Credit::Discount;
# ABSTRACT: a credit created because the user got a discount on some service
use Moose::Role;

use Moonpig::Types qw(GUID);

use namespace::autoclean;

with(
  'Moonpig::Role::Credit',
);

sub as_string { "discount" }

# There should be some member data here describing the coupon or discount that this
# represents

1;

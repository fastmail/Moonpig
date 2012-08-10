package Moonpig::Role::Discount::CombiningDiscount;
# ABSTRACT: a discount that can combine its discount with another
use Moose::Role;

use Moonpig::Types qw(NonBlankLine);

use namespace::autoclean;

with(
  'Moonpig::Role::Discount',
);

has combining_discount_key => (
  is  => 'ro',
  isa => NonBlankLine,
  required => 1,
);

1;


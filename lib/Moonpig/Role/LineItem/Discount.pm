package Moonpig::Role::LineItem::Discount;
# ABSTRACT: a charge that requires that its amount is negative

use Moose::Role;
use Moonpig::Types qw(NegativeMillicents);

use namespace::autoclean;

with(
  'Moonpig::Role::LineItem',
);

sub check_amount {
  my ($self, $amount) = @_;
  NegativeMillicents->assert_valid($amount);
}

1;

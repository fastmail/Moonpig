package Moonpig::Role::LineItem::RequiresZeroAmount;
use Moose::Role;
# ABSTRACT: a charge that requires that its amount is zero
use Moonpig::Types qw(ZeroMillicents);

use namespace::autoclean;

sub check_amount {
  my ($self, $amount) = @_;
  ZeroMillicents->assert_valid($amount);
}

1;

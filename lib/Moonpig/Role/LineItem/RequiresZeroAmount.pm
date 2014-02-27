package Moonpig::Role::LineItem::RequiresZeroAmount;
# ABSTRACT: a charge that requires that its amount is zero

use Moose::Role;
use Moonpig::Types qw(ZeroMillicents);

use namespace::autoclean;

sub check_amount {
  my ($self, $amount) = @_;
  ZeroMillicents->assert_valid($amount);
}

1;

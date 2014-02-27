package Moonpig::Role::LineItem::RequiresPositiveAmount;
# ABSTRACT: a charge that requires that its amount is positive

use Moose::Role;
use Moonpig::Types qw(PositiveMillicents);

use namespace::autoclean;

sub check_amount {
  my ($self, $amount) = @_;
  PositiveMillicents->assert_valid($amount);
}

1;

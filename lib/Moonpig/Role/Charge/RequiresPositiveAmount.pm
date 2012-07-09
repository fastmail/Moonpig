package Moonpig::Role::Charge::RequiresPositiveAmount;
use Moose::Role;
# ABSTRACT: a charge that requires that its amount is positive
use Moonpig::Types qw(PositiveMillicents);

use namespace::autoclean;

sub check_amount {
  my ($self, $amount) = @_;
  PositiveMillicents->assert_valid($amount);
}

1;

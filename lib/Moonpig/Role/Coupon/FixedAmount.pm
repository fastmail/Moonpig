package Moonpig::Role::Coupon::FixedAmount;
# ABSTRACT: a flat discount
use Moose::Role;

use Moonpig;
use Moonpig::Types qw(NonNegativeMillicents);

with(
  'Moonpig::Role::Coupon',
);

use namespace::autoclean;

# If the deal is that you get the service at $3.79 off, then this should be cents(379).
has flat_discount_amount => (
  is => 'ro',
  isa => NonNegativeMillicents,
  default => 0,
);

sub discount_amount_for {
  my ($self, $charge) = @_;
  return $self->flat_discount_amount;
}

1;

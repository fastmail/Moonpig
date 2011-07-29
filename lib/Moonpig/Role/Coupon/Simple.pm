package Moonpig::Role::Coupon::Simple;
# ABSTRACT: a disount for paying for a certain servive
use Moose::Role;

use List::Util qw(min);
use Moonpig::Types qw(NonNegativeMillicents Time);
use Moonpig;
use Moose::Util::TypeConstraints;
use MooseX::Types::Moose qw(Num);

with(
  'Moonpig::Role::Coupon',
);

use namespace::autoclean;

# If the deal is that you get the service at 15% off, then this should be 0.15.
has discount_rate => (
  is => 'ro',
  isa => subtype(Num, { where => sub { 0 <= $_ && $_ <= 1 } }),
  default => 0,
);

# If the deal is that you get the service at $3.79 off, then this should be cents(379).
has flat_discount_amount => (
  is => 'ro',
  isa => NonNegativeMillicents,
  default => 0,
);

sub discount_amount_for {
  my ($self, $charge) = @_;
  my $charge_amount = $charge->amount;
  my $discount = $charge_amount * $self->discount_rate + $self->flat_discount_amount;
  return min($discount, $charge_amount);
}

1;

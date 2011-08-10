package Moonpig::Role::Coupon::BulkDiscount;
# ABSTRACT: 10% discount for bulk purchases
use Moose::Role;

use List::Util qw(min);
use Moonpig::Types qw(NonNegativeMillicents Time);
use Moonpig;
use Moonpig::Util qw(percent);
use Moose::Util::TypeConstraints;
use MooseX::Types::Moose qw(Num);

with(
  'Moonpig::Role::Coupon',
  'Moonpig::Role::Coupon::RequiredTags',
);

use namespace::autoclean;

# Nonprofits already get a 10% discount.  Their bulk purchase discount is smaller:
# it is calculated to bring their total discount to 15%.
# (9/10 * 17/18 = 17/20 = 85%)
sub discount_amount_for {
  my ($self, $charge) = @_;
  my $charge_amount = $charge->amount;
  my $discount_rate = $charge->has_tag('nonprofit') ? 1/18 : 1/10;
  my $discount = $charge_amount * $discount_rate;
  return min($discount, $charge_amount);
}

1;

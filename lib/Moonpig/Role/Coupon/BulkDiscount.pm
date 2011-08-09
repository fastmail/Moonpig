package Moonpig::Role::Coupon::BulkDiscount;
# ABSTRACT: a disount for paying for a certain servive
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

sub discount_amount_for {
  my ($self, $charge) = @_;
  my $charge_amount = $charge->amount;
  my $discount_rate = $charge->has_tag('nonprofit') ? 1/18 : 1/10;
  my $discount = $charge_amount * $discount_rate;
  return min($discount, $charge_amount);
}

1;

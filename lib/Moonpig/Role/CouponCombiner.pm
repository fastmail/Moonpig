package Moonpig::Role::CouponCombiner;
# ABSTRACT: a helper that applies coupons to charge structures
use Moonpig;
use Moose::Role;

use List::AllUtils qw(max);
use Moonpig::Types qw(Ledger);

use namespace::autoclean;

# not a LedgerComponent because a ledger doesn't hang on to its combiner
has ledger => (
  is   => 'ro',
  isa  => Ledger,
  required => 1,
  weak_ref => 1,
);

sub apply_coupons_to_charge_struct {
  my ($self, $struct) = @_;

  # No coupons?  No munging.
  my @coupons = $self->ledger->coupons;
  return unless @coupons;

  my %by_key;

  for my $coupon (@coupons) {
    next unless my $instruction = $coupon->instruction_for_charge($struct);

    # Instructions may contain only:
    #   description
    #   discount_pct
    #   XXX: add_tags
    $instruction->{coupon} = $coupon;

    my $key = $coupon->guid;

    if ($coupon->does('Moonpig::Role::Coupon::CombiningDiscount')) {
      $key = $coupon->combining_discount_key;
    }

    push @{ $by_key{ $key } }, $instruction;
  }

  my @line_items;

  for my $key (sort keys %by_key) {
    my $total_discount;

    for my $instruction (@{ $by_key{ $key } }) {
      my $discount = int $struct->{amount} * $instruction->{discount_pct};
      $total_discount += $discount;

      # XXX: push @line_items, { ... };
      # XXX: add_tags
    }

    $struct->{amount} = max(0, $struct->{amount} - $total_discount);
  }

  return ();
}

sub line_item {
  my ($self, $desc) = @_;
  return ();  # XXX UNIMPLEMENTED
  # return class("LineItem")->new({ });
}

1;

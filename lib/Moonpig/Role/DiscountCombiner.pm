package Moonpig::Role::DiscountCombiner;
# ABSTRACT: a helper that applies discounts to charge structures
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

sub apply_discounts_to_charge_struct {
  my ($self, $struct) = @_;

  # No discounts?  No munging.
  my @discounts = $self->ledger->discounts;
  return unless @discounts;

  my %by_key;

  for my $discount (@discounts) {
    next unless my $instruction = $discount->instruction_for_charge($struct);

    # Instructions may contain only:
    #   description
    #   discount_pct
    #   XXX: add_tags
    $instruction->{discount} = $discount;

    my $key = $discount->guid;

    if ($discount->does('Moonpig::Role::Discount::CombiningDiscount')) {
      $key = $discount->combining_discount_key;
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

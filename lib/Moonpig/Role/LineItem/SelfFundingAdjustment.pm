package Moonpig::Role::LineItem::SelfFundingAdjustment;
# ABSTRACT: a magic line item that adjusts its owner's self_funding_credit_amount

use Moonpig;
use Moonpig::Types qw(NonNegativeMillicents);

use Moose::Role;
use Moonpig::Behavior::Packable;
with ('Moonpig::Role::LineItem',
      'Moonpig::Role::LineItem::Note',
      'Moonpig::Role::LineItem::Active',
      'Moonpig::Role::LineItem::Abandonable',
     );

has adjustment_amount => (
  is => 'ro',
  isa => NonNegativeMillicents,
  required => 1,
);

sub when_paid {
  my ($self) = @_;
  $self->owner->adjust_self_funding_credit_amount($self->adjustment_amount);
}

PARTIAL_PACK {
  my ($self) = @_;
  return { line_item_adjustment_amount => $self->adjustment_amount };
};


1;

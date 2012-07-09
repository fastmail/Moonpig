package Moonpig::Role::LineItem::PsyncB5G1Magic;
# ABSTRACT: a magic line item that adjusts its owner's self_funding_credit_amount
use Moonpig;
use Moonpig::Types qw(PositiveMillicents);

use Moose::Role;
with ('Moonpig::Role::LineItem',
      'Moonpig::Role::InvoiceCharge::Active',
     );

has adjustment_amount => (
  is => 'ro',
  isa => PositiveMillicents,
  required => 1,
);

sub when_paid {
  my ($self) = @_;
  $self->owner->adjust_self_funding_credit_amount($self->adjustment_amount);
}

1;

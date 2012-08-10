package Moonpig::Role::Discount::FixedPercentage;
# ABSTRACT: a percentage discount
use Moose::Role;

use Moonpig;
use Moose::Util::TypeConstraints;
use MooseX::Types::Moose qw(Num);

with(
  'Moonpig::Role::Discount',
);

use namespace::autoclean;

# If the deal is that you get the service at 15% off, then this should be 0.15.
has discount_rate => (
  is => 'ro',
  isa => subtype(Num, { where => sub { 0 <= $_ && $_ <= 1 } }),
  default => 0,
);

sub instruction_for_charge {
  my ($self, $args) = @_;

  return {
    description  => $self->description,
    discount_pct => $self->discount_rate,
  };
}

1;

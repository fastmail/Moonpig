package Moonpig::Role::Coupon::FixedPercentage;
# ABSTRACT: a percentage discount
use Moose::Role;

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

sub adjust_charge_args {
  my ($self, $args) = @_;
  my $percent = sprintf "%2d%%", 100 * $self->discount_rate;
  $args->{description} .= " (discounted $percent)";
  my $discount = $args->{amount} * $self->discount_rate;
  $args->{amount} -= $discount;
  return $self->line_item($self->description . ": $percent discount");
}

1;

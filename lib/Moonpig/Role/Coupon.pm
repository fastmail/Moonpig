package Moonpig::Role::Coupon;
# ABSTRACT: a discount for paying for a certain service
use Moonpig;
use Moonpig::Types qw(Factory Time TimeInterval);
use Moonpig::Util qw(class);
use Moose::Role;

with(
  'Moonpig::Role::CanExpire',
  'Moonpig::Role::ConsumerComponent',
  'Moonpig::Role::HasCreatedAt',
  'Moonpig::Role::HasGuid',
);

use namespace::autoclean;

has description => (
  is => 'ro',
  isa => 'Str',
  required => 1,
);

# Return true/false indicating whether to adjust the charge arguments
requires 'applies_to_charge';

around applies_to_charge => sub {
  my ($orig, $self, @args) = @_;
  return $self->is_expired ? () : $self->$orig(@args);
};

# adjust the charge arguments and return line items for adjustments
requires 'adjust_charge_args';

after adjust_charge_args => sub {
  my ($self, @args) = @_;
  $self->mark_applied;
};

sub mark_applied { } # Decorated by Coupon::SingleUse for example

sub line_item {
  my ($self, $desc) = @_;
  return ();  # XXX UNIMPLEMENTED
  class("LineItem")->new({
    consumer => $self->owner,
    description => $desc,
    tags => $self->tags,
  });
}

1;

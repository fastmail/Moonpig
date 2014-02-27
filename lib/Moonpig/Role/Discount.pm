package Moonpig::Role::Discount;
# ABSTRACT: a discount for paying for a certain service

use Moonpig;
use Moonpig::Types qw(Factory Time TimeInterval);
use Moonpig::Util qw(class);
use Moose::Role;

with(
  'Moonpig::Role::CanExpire',
  'Moonpig::Role::HasCreatedAt',
  'Moonpig::Role::HasGuid',
  'Moonpig::Role::HasTagset' => {} ,
  'Moonpig::Role::LedgerComponent',
);

use Moonpig::Behavior::Packable;

use namespace::autoclean;

has description => (
  is => 'ro',
  isa => 'Str',
  required => 1,
);

# Return true/false indicating whether to adjust the charge arguments
requires 'applies_to_charge';

around applies_to_charge => sub {
  my ($orig, $self, $args) = @_;
  return $self->is_expired ? () : $self->$orig($args);
};

# tells the DiscountCombiner what to do
requires 'instruction_for_charge';

around instruction_for_charge => sub {
  my ($orig, $self, $struct) = @_;
  return unless $self->applies_to_charge($struct);
  push @{$struct->{tags}}, $self->taglist;
  return $self->$orig($struct);
};

PARTIAL_PACK {
  return {
    description => $_[0]->description,
  };
};

1;

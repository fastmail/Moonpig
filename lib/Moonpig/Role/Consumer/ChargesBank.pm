package Moonpig::Role::Consumer::ChargesBank;
# ABSTRACT: a consumer that can issue charges
use Moose::Role;
with(
  'Moonpig::Role::Consumer',
);

use Moonpig::Types qw(TimeInterval);
use MooseX::Types::Moose qw(ArrayRef);

use namespace::autoclean;

has charge_tags => (
  is  => 'ro',
  isa => ArrayRef,
  required => 1,
);

# When the object has less than this long to live, it will
# start posting low-balance events to its successor, or to itself if
# it has no successor
has old_age => (
  is => 'ro',
  required => 1,
  isa => TimeInterval,
);

1;

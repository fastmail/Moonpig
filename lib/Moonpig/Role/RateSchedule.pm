package Moonpig::Role::RateSchedule;

# ABSTRACT: can calculate the price charged to consume an amount of a commodity

use Moose::Role;
with(
  'Moonpig::Role::HasGuid',
  'Moonpig::Role::StubBuild',
);

use Moonpig::Types qw(Millicents MRI);
use Moonpig::Logger '$Logger';
use MooseX::Types::Moose qw(Str);

use namespace::autoclean;

has commodity_name => (
  is => 'ro',
  isa => Str,
  default => sub { "things" },
);

# takes a non-negative integer N of the nunber of units desired,
# and returns the cost in millicents
requires qw(cost_of);

1;

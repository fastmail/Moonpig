package Moonpig::Role::Consumer::ByTime::FixedCost;
# ABSTRACT: a consumer that charges steadily as time passes
use Moose::Role;

use Moonpig;

use Moonpig::Logger '$Logger';
use Moonpig::Types qw(PositiveMillicents);

use namespace::autoclean;

has cost_amount => (
  is => 'ro',
  required => 1,
  isa => PositiveMillicents,
);

sub cost_amount_on {
  $_[0]->cost_amount;
}

with(
  'Moonpig::Role::Consumer::ByTime',
);

1;

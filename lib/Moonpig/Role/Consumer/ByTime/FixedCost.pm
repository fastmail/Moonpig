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

sub costs_on {
  return ($_[0]->charge_description, $_[0]->cost_amount);
}

# Description for charge.  You will probably want to override this method
has charge_description => (
  is => 'ro',
  isa => 'Str',
  required => 1,
);

with(
  'Moonpig::Role::Consumer::ByTime',
);

1;

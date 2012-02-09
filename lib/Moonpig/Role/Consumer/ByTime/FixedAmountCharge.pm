package Moonpig::Role::Consumer::ByTime::FixedAmountCharge;
# ABSTRACT: a consumer that charges steadily as time passes
use Moose::Role;

use Moonpig;
use Moonpig::Logger '$Logger';
use Moonpig::Trait::Copy;
use Moonpig::Types qw(PositiveMillicents);

use namespace::autoclean;

with(
  'Moonpig::Role::Consumer::ByTime',
);

has charge_amount => (
  is => 'ro',
  required => 1,
  isa => PositiveMillicents,
  traits => [ qw(Copy) ],
);

# Does not vary with time
sub charge_pairs_on {
  return ($_[0]->charge_description, $_[0]->charge_amount);
}

# Description for charge.  You will probably want to override this method
has charge_description => (
  is => 'ro',
  isa => 'Str',
  required => 1,
  traits => [ qw(Copy) ],
);

1;

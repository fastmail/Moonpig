package Moonpig::Role::Consumer::ByTime;
use DateTime;
use DateTime::Infinite;
use Moose::Role;
use namespace::autoclean;

with(
  'Moonpig::Role::Consumer',
);

use Moonpig::Types qw(Millicents);

# How often I charge the bank, in days
has charge_frequency => (
  is => 'ro',
  default => sub { 1 },
  isa => 'Num',
);

# How much I cost to own, in millicents per period
has cost_amount => (
  is => 'ro',
  required => 1,
  isa => 'Num',
);

#  XXX this is period in days, which is not quite right, since a
#  charge of $10 per month or $20 per year is not any fixed number of
#  days, For example a charge of $20 annually, charged every day,
#  works out to 5479 mc per day in common years, but 5464 mc per day
#  in leap years.  -- 2010-10-26 mjd

has cost_period => (
   is => 'ro',
   required => 1,
   isa => 'Num',   # XXX in days
);

# I start generating low-balance events when my bank balance falls below this much
has min_balance => (
  is => 'ro',
  isa => Millicents,
  required => 1,
);

# Last time I charged the bank
has last_charge_date => (
  is => 'rw',
  isa => 'DateTime',
  default => sub { DateTime::Infinite::Past->new },
);



1;

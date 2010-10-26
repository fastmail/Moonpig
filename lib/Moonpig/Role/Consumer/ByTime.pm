package Moonpig::Role::Consumer::ByTime;
use Moose::Role;

with(
  'Moonpig::Role::Consumer',
);

use Moonpig::Types qw(Ledger Millicents);

use namespace::autoclean;


1;

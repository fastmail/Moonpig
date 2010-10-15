package Moonpig::Role::Bank;
use Moose::Role;
with(
  'Moonpig::Role::HasGuid',
);

use Moonpig::Types qw(Ledger Millicents);

use namespace::autoclean;

has amount => (
  is  => 'ro',
  isa =>  Millicents,
  coerce   => 1,
  required => 1,
);

has ledger => (
  is   => 'ro',
  isa  => Ledger,
  required => 1,
);

# mechanism to get xfers

1;

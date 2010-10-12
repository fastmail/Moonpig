package Moonpig::Role::Bank;
use Moose::Role;
use Moonpig::Types qw(Millicents);

use namespace::autoclean;

has amount => (
  is  => 'ro',
  isa =>  Millicents,
  coerce   => 1,
  required => 1,
);

# mechanism to get xfers

1;

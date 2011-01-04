package Moonpig::Role::Payment;
use Moose::Role;
with(
  'Moonpig::Role::Refundable',
);

use Moonpig;
use Moonpig::DateTime;
use Moonpig::Types qw(Millicents);

use namespace::autoclean;

requires 'as_string';

has received_at => (
  is   => 'ro',
  isa  => 'Moonpig::DateTime',
  default  => sub { Moonpig->env->now },
  required => 1,
);

has amount => (
  is  => 'ro',
  isa => Millicents,
  coerce => 1,
);

# TODO: some kind of method to create a Credit object on a ledger and then
# associate us with it should go here -- rjbs, 2011-01-04

1;

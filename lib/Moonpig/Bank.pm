package Moonpig::Bank;
use Moose;
use Moonpig::Types qw(MoneyAmount);

has value => (
  is  => 'ro',
  isa =>  MoneyAmount,
  coerce   => 1,
  required => 1,
);

1;

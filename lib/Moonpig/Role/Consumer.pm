package Moonpig::Role::Consumer;
use Moose::Role;
use MooseX::SetOnce;

use namespace::autoclean;

has bank => (
  is   => 'rw',
  does => 'Moonpig::Role::Bank',
  traits    => [ qw(SetOnce) ],
  predicate => 'has_bank',
);

has replacement => (
  is   => 'rw',
  does => 'Moonpig::Role::Consumer',
  traits    => [ qw(SetOnce) ],
  predicate => 'has_replacement',
);

# mechanism to get xfers

1;

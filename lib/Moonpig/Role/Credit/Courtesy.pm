package Moonpig::Role::Credit::Courtesy;
use Moose::Role;

use namespace::autoclean;

with 'Moonpig::Role::Credit';

has reason => (
  is   => 'ro',
  isa  => 'Str',
  required => 1,
);

1;

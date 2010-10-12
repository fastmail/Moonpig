package Moonpig::Role::Charge;
use Moose::Role;

use MooseX::Types::Moose qw(Str);
use Moonpig::Types qw(Millicents);

use namespace::autoclean;

has description => (
  is  => 'ro',
  isa => Str,
  required => 1,
);

has amount => (
  is  => 'ro',
  isa => Millicents,
  required => 1,
);

1;

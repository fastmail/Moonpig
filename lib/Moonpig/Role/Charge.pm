package Moonpig::Role::Charge;
use Moose::Role;

use MooseX::Types::Moose qw(Str);
use Moonpig;
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
  coerce   => 1,
  required => 1,
);

has date => (
  is      => 'ro',
  isa     => 'DateTime',
  default  => sub { Moonpig->env->now() },
);

1;

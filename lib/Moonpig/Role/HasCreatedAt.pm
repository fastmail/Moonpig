package Moonpig::Role::HasCreatedAt;
use Moose::Role;
use namespace::autoclean;

use Moonpig::Types qw(Time);

has created_at => (
  is => 'ro',
  isa => Time,
  default  => sub { Moonpig->env->now },
  init_arg => undef,
);

1;

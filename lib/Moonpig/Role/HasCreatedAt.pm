package Moonpig::Role::HasCreatedAt;
use Moose::Role;
# ABSTRACT: a thing that has the created_at attribute

use namespace::autoclean;

use Moonpig::Types qw(Time);

use Moonpig::Behavior::Packable;

has created_at => (
  is => 'ro',
  isa => Time,
  default  => sub { Moonpig->env->now },
  init_arg => undef,
);

PARTIAL_PACK {
  return {
    created_at => $_[0]->created_at,
  };
};

1;

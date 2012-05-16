package Moonpig::Role::Consumer::Dummy;
# ABSTRACT: a minimal consumer for testing

use Carp qw(confess croak);
use Moose::Role;

with(
  'Moonpig::Role::Consumer',
  'Moonpig::Role::HandlesEvents',
  'Moonpig::Role::StubBuild',
);

sub charge { }

use namespace::autoclean;

1;

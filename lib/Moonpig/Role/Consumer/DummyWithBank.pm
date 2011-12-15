package Moonpig::Role::Consumer::DummyWithBank;
# ABSTRACT: a minimal consumer for testing

use Carp qw(confess croak);
use Moose::Role;

with(
  'Moonpig::Role::Consumer',
  'Moonpig::Role::Consumer::Charges',
  'Moonpig::Role::HandlesEvents',
  'Moonpig::Role::StubBuild',
);

use namespace::autoclean;

1;

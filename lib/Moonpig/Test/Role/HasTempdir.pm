package Moonpig::Test::Role::HasTempdir;
# ABSTRACT: a test routine with a new tempdir for each test

use Test::Routine;

use File::Temp qw(tempdir);

use namespace::clean;

has tempdir => (
  is   => 'ro',
  isa  => 'Str',
  lazy => 1,
  default => sub { tempdir(CLEANUP => 1 ) },
  clearer => 'clear_tempdir',
);

before run_test => sub { $_[0]->clear_tempdir };

1;

package Moonpig::Test::Role::UsesStorage;
use Test::Routine;
# ABSTRACT: a test routine that provides fresh storage per test

with(
  'Moonpig::Test::Role::HasTempdir',
);

use namespace::clean;

around run_test => sub {
  my ($orig, $self, @rest) = @_;

  local $ENV{MOONPIG_STORAGE_ROOT} = $self->tempdir;
  $self->$orig(@rest);

  $self->_last_chance_before_test_ends;

  Moonpig->env->clear_storage;
};

sub _last_chance_before_test_ends {}

1;


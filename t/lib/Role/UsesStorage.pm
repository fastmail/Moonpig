package t::lib::Role::UsesStorage;
use Test::Routine;

with(
  't::lib::Role::HasTempdir',
);

use namespace::clean;

around run_test => sub {
  my ($orig, $self, @rest) = @_;

  local $ENV{MOONPIG_STORAGE_ROOT} = $self->tempdir;
  $self->$orig(@rest);

  Moonpig->env->clear_storage;
};

1;


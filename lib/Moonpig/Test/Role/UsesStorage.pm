package Moonpig::Test::Role::UsesStorage;
use Test::Routine;

with(
  'Moonpig::Test::Role::HasTempdir',
);

use namespace::clean;

sub heartbeat_and_send_mail {
  my $self   = shift;
  my $ledger = shift;

  Moonpig->env->storage->do_rw(sub {
    $ledger->heartbeat;
  });

  Moonpig->env->process_email_queue;
}

around run_test => sub {
  my ($orig, $self, @rest) = @_;

  local $ENV{MOONPIG_STORAGE_ROOT} = $self->tempdir;
  $self->$orig(@rest);

  Moonpig->env->clear_storage;
};

1;


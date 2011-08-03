package Moonpig::Role::Storage;
use Moose::Role;

use Moonpig::Context::Test -all, '$Context';

use namespace::autoclean;

requires 'do_rw';
requires 'do_ro';

requires 'queue_job__';
requires 'iterate_jobs';
requires 'undone_jobs_for_ledger';

requires 'save_ledger';
requires 'ledger_guids';

requires 'retrieve_ledger_for_guid';
requires 'retrieve_ledger_for_xid';

around retrieve_ledger_for_guid => sub {
  my ($orig, $self, @arg) = @_;

  return unless my $ledger = $self->$orig(@arg);

  $Context->stack->current_frame->add_memorandum($ledger);
  return $ledger;
};

1;

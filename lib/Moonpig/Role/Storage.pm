package Moonpig::Role::Storage;
use Moose::Role;

use Moonpig::Context::Test -all, '$Context';

use namespace::autoclean;

requires 'do_rw';
requires 'do_ro';

requires 'do_with_ledgers';

# instead of a hash of name-to-guid mappings, get just a single guid
# and instead of passing the code a hash of name-to-ledger mappings,
# just pass a single guid
sub do_with_ledger {
  my ($self, $guid, $code, $opts) = @_;
  $self->do_with_ledgers({ ledger => $guid }, sub { $code->($_[0]{ledger}) }, $opts);
}

sub do_with_this_ledger {
  my ($self, $ledger) = @_;
  die "unimplemented";
}

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

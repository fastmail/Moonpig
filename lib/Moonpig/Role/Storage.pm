package Moonpig::Role::Storage;
use Moose::Role;
# ABSTRACT: a backend storage engine for Moonpig

use Carp 'croak';

use namespace::autoclean;

requires 'do_rw';
requires 'do_ro';

requires 'do_with_ledgers';

# instead of a hash of name-to-guid mappings, get just a single guid
# and instead of passing the code a hash of name-to-ledger mappings,
# just pass a single guid
sub do_with_ledger {
  if (@_ == 3) {
    splice @_, 1, 0, {}; # $opts was omitted, so splice it in
  }
  my ($self, $opts, $guid, $code) = @_;
  local $Carp::Internal{ (__PACKAGE__) }+=1;
  $self->do_with_ledgers($opts, [ $guid ], sub { $code->($_[0]) });
}

sub do_rw_with_ledger {
  if (@_ == 3) {
    splice @_, 1, 0, {}; # $opts was omitted, so splice it in
  }
  my ($self, $opts, $guid, $code) = @_;
  croak "ro option forbidden in do_rw_with_ledger" if exists $opts->{ro};
  local $Carp::Internal{ (__PACKAGE__) }+=1;
  $self->do_with_ledger({ %$opts, ro => 0 }, $guid, $code);
}

sub do_ro_with_ledger {
  if (@_ == 3) {
    splice @_, 1, 0, {}; # $opts was omitted, so splice it in
  }
  my ($self, $opts, $guid, $code) = @_;
  croak "ro option forbidden in do_ro_with_ledger" if exists $opts->{ro};
  local $Carp::Internal{ (__PACKAGE__) }+=1;
  $self->do_with_ledger({ %$opts, ro => 1 }, $guid, $code);
}

# Take a prefabricated ledger, and run a transaction with it
# WARNING: the ledger variable may become invalid after the transaction completes,
# meaning that it may no longer reflect the correct state of the ledger!
# This method is for testing only.
sub do_with_this_ledger {
  if (@_ == 3) {
    splice @_, 1, 0, {}; # $opts was omitted, so splice it in
  }
  my ($self, $opts, $ledger, $code) = @_;
  local $Carp::Internal{ (__PACKAGE__) }+=1;
  $self->do_rw(sub {
    $ledger->save();
    $self->do_with_ledger($opts, $ledger->guid, $code);
  });
}

requires 'queue_job';
requires 'iterate_jobs';
requires 'undone_jobs_for_ledger';

requires 'save_ledger';
requires 'ledger_guids';

requires 'retrieve_ledger_for_guid';
requires 'retrieve_ledger_for_ident';
requires 'retrieve_ledger_for_xid';

1;

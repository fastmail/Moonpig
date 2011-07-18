package Moonpig::Role::Storage;
use Moose::Role;

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

1;

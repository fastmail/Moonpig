package Moonpig::Role::Credit::Transient;
# ABSTRACT: a credit created by inter-ledger transfer
use Moose::Role;

use Moonpig::Types qw(GUID);

use namespace::autoclean;

with(
  'Moonpig::Role::Credit',
);

sub as_string { "transient credit" }

has [qw(source_ledger_guid source_guid)] => (
  is => 'ro',
  isa => GUID,
  required => 1,
);

1;

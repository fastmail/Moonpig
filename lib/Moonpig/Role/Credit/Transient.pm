package Moonpig::Role::Credit::Transient;
# ABSTRACT: a credit created because a bank was transferred from another ledger
use Moose::Role;

use Moonpig::Types qw(GUID);

use namespace::autoclean;

with(
  'Moonpig::Role::Credit',
);

sub as_string { "transient credit" }

has [qw(source_ledger_guid source_consumer_guid source_bank_guid)] => (
  is => 'ro',
  isa => GUID,
  required => 1,
);

1;

package Moonpig::Role::LedgerComponent;
# ABSTRACT: something that's part of a ledger and links back to it
use Moose::Role;

use Moonpig::Types qw(Ledger);

use namespace::autoclean;

has ledger => (
  is   => 'ro',
  isa  => Ledger,
  required => 1,
  weak_ref => 1,
);

1;

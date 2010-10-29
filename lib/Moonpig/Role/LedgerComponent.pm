package Moonpig::Role::LedgerComponent;
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

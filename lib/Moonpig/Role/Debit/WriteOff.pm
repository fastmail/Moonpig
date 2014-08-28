package Moonpig::Role::Debit::WriteOff;
# ABSTRACT: a debit reflecting money lost through charge reversal, etc.

use Moose::Role;

use namespace::autoclean;

with 'Moonpig::Role::Debit';

1;

package Moonpig::Role::Debit::WriteOff;
use Moose::Role;
# ABSTRACT: a debit reflecting money lost through charge reversal, etc.

use namespace::autoclean;

with 'Moonpig::Role::Debit';

1;

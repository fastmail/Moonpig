package Moonpig::Role::Credit::Imported;
# ABSTRACT: a (non-refundable) credit imported from the old billing system
use Moose::Role;

with('Moonpig::Role::Credit');

use namespace::autoclean;

1;

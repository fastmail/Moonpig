package Moonpig::Role::Credit::Refundable;
# ABSTRACT: a credit that can be refunded
use Moose::Role;

with('Moonpig::Role::Credit');

use namespace::autoclean;

requires 'issue_refund';

1;

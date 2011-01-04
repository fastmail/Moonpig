package Moonpig::Role::Refundable;
use Moose::Role;

use namespace::autoclean;

requires 'issue_refund';

1;

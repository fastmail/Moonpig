package Moonpig::Role::Refundable;
# ABSTRACT: something (generally a credit) that can be refunded
use Moose::Role;

use namespace::autoclean;

requires 'issue_refund';

1;

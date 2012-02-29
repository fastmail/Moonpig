package Moonpig::Role::Credit::Imported;
# ABSTRACT: a (non-refundable) credit imported from the old billing system
use Moose::Role;

with('Moonpig::Role::Credit');

use namespace::autoclean;

sub as_string { 'credit imported from legacy billing system' }

has old_payment_info => (
  is  => 'ro',
  isa => 'HashRef',
  required => 1,
);

1;

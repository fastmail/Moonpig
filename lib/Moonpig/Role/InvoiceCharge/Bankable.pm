package Moonpig::Role::InvoiceCharge::Bankable;
# ABSTRACT: a charge that, when paid, should have a bank created for the paid amount
use Moose::Role;

with(
  'Moonpig::Role::InvoiceCharge',
);

use Moonpig::Util qw(class);

use namespace::autoclean;

1;

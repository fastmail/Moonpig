package Moonpig::Role::InvoiceCharge::Bankable;
# ABSTRACT: a charge that, when paid, should have a bank created for the paid amount
use Moose::Role;

# You might want this to be an InvoiceCharge::Active, with a when_paid
# method that creates the bank and associates it with the consumer.
# But that doesn't work, because the same consumer might put in
# multiple InvoiceCharges, and the consumer needs to have one single
# bank for the total.
with(
  'Moonpig::Role::InvoiceCharge',
);

use Moonpig::Util qw(class);

use namespace::autoclean;

1;

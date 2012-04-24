package Moonpig::Role::LineItem;
# ABSTRACT: a non-charge line item on an invoice
use Moose::Role;
with ('Moonpig::Role::InvoiceCharge');

1;

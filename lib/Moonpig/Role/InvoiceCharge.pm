package Moonpig::Role::InvoiceCharge;
use Moose::Role;
with(
  'Moonpig::Role::Charge',
  'Moonpig::Role::Charge::HandlesEvents',
);

use namespace::autoclean;

1;

package Moonpig::Role::Credit::Imported::Refundable;
# ABSTRACT: a (refundable) credit imported from the old billing system
use Moose::Role;

with(
  'Moonpig::Role::Credit::Imported',
  'Moonpig::Role::Credit::Refundable::ViaCustSrv',
);

use namespace::autoclean;

1;

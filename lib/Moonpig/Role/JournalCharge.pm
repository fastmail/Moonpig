package Moonpig::Role::JournalCharge;
# ABSTRACT: a charge placed on an journal

use Moose::Role;
with(
  'Moonpig::Role::LineItem',
  'Moonpig::Role::LineItem::RequiresPositiveAmount',
);

use namespace::autoclean;

1;

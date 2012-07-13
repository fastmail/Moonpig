package Moonpig::Role::JournalCharge;
use Moose::Role;
# ABSTRACT: a charge placed on an journal
with(
  'Moonpig::Role::LineItem',
  'Moonpig::Role::LineItem::RequiresPositiveAmount',
);

use namespace::autoclean;

1;

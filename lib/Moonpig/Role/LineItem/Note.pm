package Moonpig::Role::LineItem::Note;
# ABSTRACT: a charge that requires that its amount is zero

use Moose::Role;

with(
  'Moonpig::Role::LineItem',
  'Moonpig::Role::LineItem::RequiresZeroAmount',
  'Moonpig::Role::LineItem::Abandonable',
);

use namespace::autoclean;

1;

package Moonpig::Role::LineItem::Note;
use Moose::Role;
# ABSTRACT: a charge that requires that its amount is zero

with(
  'Moonpig::Role::LineItem',
  'Moonpig::Role::LineItem::RequiresZeroAmount',
);

use namespace::autoclean;

1;

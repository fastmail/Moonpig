package Moonpig::Role::Invoice;
use Moose::Role;

use namespace::autoclean;

has cost_tree => (
  is   => 'ro',
  does => 'Moonpig::Role::CostTree',
  required => 1,
  default  => sub { confess "we should really have a default cost tree" },
);

sub total_amt { confess "..."; }

1;

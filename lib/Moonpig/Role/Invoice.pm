package Moonpig::Role::Invoice;
use Moose::Role;

use namespace::autoclean;

has cost_tree => (
  is   => 'ro',
  does => 'Moonpig::Role::CostTree',
  required => 1,
  default  => sub { confess "we should really have a default cost tree" },
);

# TODO: make sure that charges added to this invoice have dates that
# precede this date. 2010-10-17 mjd@icgroup.com
has date => (
  is  => 'ro',
  required => 1,
  default => sub { DateTime->now() },
  isa => 'DateTime',
);

sub total_amt { confess "..."; }

1;

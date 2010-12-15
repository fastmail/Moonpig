package Moonpig::Role::CostTreeContainer;
use Moose::Role;

use namespace::autoclean;

use Moonpig;
use Moonpig::CostTree::Basic;

has cost_tree => (
  is   => 'ro',
  does => 'Moonpig::Role::CostTree',
  default  => sub { Moonpig::CostTree::Basic->new },
  handles  => [ qw(add_charge_at total_amount) ],
);

has closed => (
  isa     => 'Bool',
  default => 0,
  traits  => [ 'Bool' ],
  reader  => 'is_closed',
  handles => {
    'close'   => 'set',
    'is_open' => 'not',
  },
);

# TODO: make sure that charges added to this container have dates that
# precede this date. 2010-10-17 mjd@icgroup.com
has date => (
  is  => 'ro',
  required => 1,
  default => sub { Moonpig->env->now() },
  isa => 'DateTime',
);

1;

package Moonpig::Test::Role::Ledger;
use Moose::Role;

has _component_name_map => (
  is => 'ro',
  isa => 'HashRef',
  traits => [ 'Hash' ],
  default => sub { {} },
  handles => {
    get_component => 'get',
  },
);

1;

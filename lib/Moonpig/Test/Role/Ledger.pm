package Moonpig::Test::Role::Ledger;
use Moose::Role;
# ABSTRACT: a role to add component-naming to ledgers for testing

has _component_name_map => (
  is => 'ro',
  isa => 'HashRef',
  traits => [ 'Hash' ],
  default => sub { {} },
  handles => {
    get_component => 'get',
    has_component => 'exists',
  },
);

sub name_component {
  my ($self, $name, $component) = @_;
  if ($self->has_component($name)) {
    require Carp;
    Carp::croak("Ledger already has a '$name' component");
  }
  $self->_component_name_map->{$name} = $component;
}

1;

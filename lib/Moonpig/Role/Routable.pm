package Moonpig::Role::Routable;
use Moose::Role;

use Moonpig::X;

use namespace::autoclean;

requires 'class_router';
requires 'instance_router';

sub route {
  my ($invocant, @rest) = @_;

  my $result = $invocant->_router->route($invocant, @rest);
}

sub _router {
  my ($invocant) = @_;

  my $router = blessed $invocant
             ? $invocant->instance_router 
             : $invocant->class_router;

  return $router;
}

1;

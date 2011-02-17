package Moonpig::Role::Routable::Disjunct;
use Moose::Role;

with(
  'Moonpig::Role::Routable',
);

use namespace::autoclean;

requires '_class_subroute';
requires '_instance_subroute';

sub _subroute {
  my ($invocant, $path) = @_;

  my $method = blessed $invocant ? '_instance_subroute' : '_class_subroute';

  return $invocant->$method($path);
}

1;

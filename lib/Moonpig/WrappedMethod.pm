package Moonpig::WrappedMethod;
use Moose;

use namespace::autoclean;

has [ map {; "$_\_method" } qw(get put post delete) ] => (
  is  => 'ro',
  isa => 'Str|CodeRef',
);

sub invoke {
  my ($self, $invocant, $method_type, $arg) = @_;

  my $method_method = join q{_}, $method_type, 'method';

  Moonpig::X::NoRoute->throw unless my $method = $self->$method_method;

  $invocant->$method($arg);
}

1;

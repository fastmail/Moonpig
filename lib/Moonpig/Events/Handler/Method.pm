package Moonpig::Events::Handler::Method;
use Moose;
with 'Moonpig::Role::EventHandler';

use MooseX::Types::Perl qw(Identifier);

use namespace::autoclean;

has method_name => (
  is  => 'ro',
  isa => Identifier,
  required => 1,
);

sub handle_event {
  my ($self, $event, $receiver, $arg) = @_;

  my $method_name = $self->method_name;
  $receiver->$method_name($event, $arg, $self);
}

1;

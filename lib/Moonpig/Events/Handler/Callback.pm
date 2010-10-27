package Moonpig::Events::Handler::Callback;
use Moose;
with 'Moonpig::Role::EventHandler';

use MooseX::Types::Moose qw(CodeRef);

use namespace::autoclean;

has callback => (
  is  => 'ro',
  isa => CodeRef,
  required => 1,
);

sub handle_event {
  my ($self, $arg) = @_;

  my $callback = $self->callback;
  $callback->($arg->{receiver}, $arg->{event_name}, $arg);
}

1;

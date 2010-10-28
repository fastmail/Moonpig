package Moonpig::Role::HandlesEvents;
use Moose::Role;

use Moonpig::Events::EventRegistry;

use MooseX::Types::Moose qw(ArrayRef HashRef);

use namespace::autoclean;

has _event_handler_registry => (
  is  => 'ro',
  isa => 'Moonpig::Events::EventRegistry',
  required => 1,
  default  => sub { Moonpig::Events::EventRegistry->new({ owner => $_[0] }) },
  handles  => [ qw(register_event_handler) ],
);

sub handle_event {
  my ($self, $event_name, $arg) = @_;
  $self->_event_handler_registry->handle_event($self, $event_name, $arg);
}

1;

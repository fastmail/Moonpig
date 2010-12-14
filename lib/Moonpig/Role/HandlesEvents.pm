package Moonpig::Role::HandlesEvents;
use Moose::Role;

use Moonpig::Events::Event;
use Moonpig::Events::EventHandlerRegistry;
use Moonpig::Events::Handler::Noop;

use MooseX::Types::Moose qw(ArrayRef HashRef);

use Moonpig::Behavior::EventHandlers;

use namespace::autoclean;

has _event_handler_registry => (
  is   => 'ro',
  isa  => 'Moonpig::Events::EventHandlerRegistry',
  lazy => 1,
  required => 1,
  default  => sub { Moonpig::Events::EventHandlerRegistry->new({
    owner => $_[0] })
  },
  handles  => [ qw(register_event_handler) ],
);

sub handle_event {
  my ($self, $event) = @_;

  $event = Moonpig::Events::Event->new($event) if ! blessed $event;

  $self->_event_handler_registry->handle_event($event, $self);
}

implicit_event_handlers {
  return { heartbeat => { noop => Moonpig::Events::Handler::Noop->new } };
};

1;

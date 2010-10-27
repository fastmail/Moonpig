package Moonpig::Events::EventRegistry;
use Moose;

use List::AllUtils qw(any first);

use Data::GUID qw(guid_string);
use Moonpig::Types qw(EventHandlerMap);
use Moonpig::X;

use namespace::autoclean;

has _handlers_for => (
  is  => 'ro',
  isa => EventHandlerMap,
  required => 1,
  default  => sub {  {}  },
);

sub _handlers_for_event {
  my ($self, $event_name) = @_;

  return $self->_handlers_for->{ $event_name } || [];
}

sub _event_handler_named {
  my ($self, $event_name, $handler_name) = @_;

  return first { $_->name eq $handler_name }
         @{ $self->_handlers_for_event( $event_name ) };
}

sub BUILD {
  my ($self) = @_;

  $self->_setup_implicit_event_handlers;
}

sub _setup_implicit_event_handlers {
  my ($self) = @_;

  my $method_name = 'implicit_event_handlers';
  if ($self->can( $method_name )) {
    foreach my $method (
      Class::MOP::class_of($self)->find_all_methods_by_name( $method_name )
    ) {
      my $handler_map = $method->{code}->execute($self);
      EventHandlerMap->assert_valid($handler_map);

      for my $event_name (keys %$handler_map) {
        my $implicit_handlers = $handler_map->{ $event_name };

        for my $handler (@$implicit_handlers) {
          next if $self->_event_handler_named($event_name, $handler->name);
          $self->register_event_handler($event_name, $handler);
        }
      }
    }
  }
}

sub register_event_handler {
  my ($self, $event_name, $handler) = @_;

  $self->_handlers_for->{ $event_name } ||= [];
  my $handler_name = $handler->name;

  if ($self->_event_handler_named($event_name, $handler_name)) {
    Moonpig::X->throw({
      ident   => 'duplicate handler',
      message => 'handler named %{handler_name}s already registered for event %{event_name}s',
      payload => {
        handler_name => $handler_name,
        event_name   => $event_name,
      },
    });
  }

  my $handlers = $self->_handlers_for->{ $event_name };
  push @$handlers, $handler;
}

sub handle_event {
  my ($self, $receiver, $event_name, $arg) = @_;

  my $handlers = $self->_handlers_for_event($event_name);

  unless (@$handlers) {
    Moonpig::X->throw({
      ident   => 'unhandled event',
      message => 'no handlers registered for event %{event_name}s',
      payload => {
        event_name => $event_name,
      },
    });
  }

  my $guid = guid_string;

  for my $handler (@$handlers) {
    $handler->handle_event({
      receiver   => $receiver,
      event_guid => $guid,
      event_name => $event_name,
      parameters => $arg,
    });
  }

  return $guid;
}

1;

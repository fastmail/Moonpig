package Moonpig::Events::EventHandlerRegistry;
# ABSTRACT: a registry of handlers, used by other objects to dispatch events

use Moose;
use MooseX::StrictConstructor;

use List::AllUtils qw(any first);

use Data::GUID qw(guid_string);
use Moonpig::Types qw(Event EventHandler EventHandlerMap);
use Moonpig::X;

use namespace::autoclean;

has _handlers_for => (
  is  => 'ro',
  isa => EventHandlerMap,
  required => 1,
  default  => sub {  {}  },
  init_arg => undef,
);

sub _handlers_for_event {
  my ($self, $event_name) = @_;

  return $self->_handlers_for->{ $event_name };
}

sub _event_handler_named {
  my ($self, $event_name, $handler_name) = @_;

  return $self->_handlers_for_event( $event_name )->{ $handler_name };
}

has owner => (
  is  => 'ro',
  isa => 'Object',
  required => 1,
  weak_ref => 1,
);

sub BUILD {
  my ($self, $arg) = @_;

  $self->_setup_implicit_event_handlers;
}

sub _setup_implicit_event_handlers {
  my ($self) = @_;
  my $owner = $self->owner;

  my $handler_map = $owner->composed_implicit_event_handlers;

  EventHandlerMap->assert_valid($handler_map);

  for my $event_name (keys %$handler_map) {
    my $implicit_handlers = $handler_map->{ $event_name };

    for my $handler_name (keys %$implicit_handlers) {
      my $handler = $implicit_handlers->{ $handler_name };
      EventHandler->assert_valid($handler);

      $handler->mark_implicit;
      $self->register_event_handler($event_name, $handler_name, $handler);
    }
  }
}

sub register_event_handler {
  my ($self, $event_name, $handler_name, $handler) = @_;

  $self->_handlers_for->{ $event_name } ||= {};

  my $old_handler = $self->_event_handler_named($event_name, $handler_name);
  if ($old_handler and $old_handler->is_explicit) {
    Moonpig::X->throw({
      ident   => 'duplicate handler',
      message => 'handler named %{handler_name}s already registered for event %{event_name}s',
      payload => {
        handler_name => $handler_name,
        event_name   => $event_name,
      },
    });
  }

  $self->_handlers_for->{ $event_name }->{ $handler_name } = $handler;
}

sub handle_event {
  my ($self, $event, $receiver) = @_;

  Event->assert_valid($event);

  my $handlers = $self->_handlers_for_event($event->ident);

  unless (grep { defined } values %$handlers) {
    Moonpig::X->throw({
      ident   => 'unhandled event',
      message => 'no handlers registered for event %{event_name}s',
      payload => {
        event_name => $event->ident,
      },
    });
  }

  my $guid = guid_string;

  for my $handler_name (sort keys %$handlers) {
    my $handler = $handlers->{ $handler_name };

    if ($ENV{MOONPIG_TRACE_EVENTS} && $handler_name ne 'noop') {
      my $rcv = $receiver->can('ident') ? $receiver->ident : "$receiver";
      warn "# Event <" . $event->ident . "> handled by "
         . "'$handler_name' in $rcv\n";
    }

    $handler->handle_event(
      $event,
      $receiver,
      {
        handler_name => $handler_name,
        event_guid   => $guid,
      }
    );
  }

  return $guid;
}

1;

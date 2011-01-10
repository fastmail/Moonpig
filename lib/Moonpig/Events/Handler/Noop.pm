package Moonpig::Events::Handler::Noop;
# ABSTRACT: an event handler that silently ignores the event
use Moose;
with 'Moonpig::Role::EventHandler';

use namespace::autoclean;

sub handle_event {
  return;
}

1;

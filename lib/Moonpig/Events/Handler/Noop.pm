package Moonpig::Events::Handler::Noop;
use Moose;
with 'Moonpig::Role::EventHandler';

use namespace::autoclean;

sub handle_event {
  return;
}

1;

package Moonpig::Charge::Basic::HandlesEvents;
use Moose;
extends 'Moonpig::Charge::Basic';

with 'Moonpig::Role::HandlesEvents';

use Moonpig::Behavior::EventHandlers;

implicit_event_handlers {
  return { paid => { noop => Moonpig::Events::Handler::Noop->new } };
};

1;

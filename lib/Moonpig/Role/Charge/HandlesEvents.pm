package Moonpig::Role::Charge::HandlesEvents;
use Moose::Role;
with(
  'Moonpig::Role::Charge',
  'Moonpig::Role::HandlesEvents',
);

use Moonpig::Behavior::EventHandlers;

implicit_event_handlers {
  return { paid => { noop => Moonpig::Events::Handler::Noop->new } };
};

1;

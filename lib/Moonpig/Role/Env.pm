package Moonpig::Role::Env;
use Moose::Role;

use Moonpig;

with(
  'Moonpig::Role::HandlesEvents',
  'Moonpig::Role::TracksTime',
);

use Moonpig::Events::Handler::Method;

use Moonpig::Behavior::EventHandlers;

requires 'handle_send_email';

implicit_event_handlers {
  return {
    'send-email' => {
      default => Moonpig::Events::Handler::Method->new('handle_send_email'),
    }
  };
};

1;

package Moonpig::Role::Consumer::ChargesPeriodically;
# ABSTRACT: a consumer that issues charges when it gets a heartbeat event

use Moose::Role;
use Moonpig::Behavior::EventHandlers;
use Moonpig::Events::Handler::Method;

requires 'charge';
with ('Moonpig::Role::HandlesEvents');

implicit_event_handlers {
  return {
    heartbeat => {
      charge => Moonpig::Events::Handler::Method->new(
        method_name => 'charge',
      ),
    },
  };
};

1;

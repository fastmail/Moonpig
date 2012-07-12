package Moonpig::Role::ChargeLike::Active;
use Moose::Role;
# ABSTRACT: a charge that does something extra when paid
with(
  'Moonpig::Role::ChargeLike',
);

use namespace::autoclean;
use Moonpig::Behavior::EventHandlers;
use Moonpig::Events::Handler::Method;
use Moonpig::Types qw(EventHandler);

implicit_event_handlers {
  return {
    'paid' => {
      'active' => Moonpig::Events::Handler::Method->new("when_paid"),
    },
  }
};

requires 'when_paid';

1;

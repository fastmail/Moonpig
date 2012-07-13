package Moonpig::Role::LineItem::Active;
use Moose::Role;
# ABSTRACT: a line item that does something extra when paid
with(
  'Moonpig::Role::LineItem',
  'Moonpig::Role::HandlesEvents',
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

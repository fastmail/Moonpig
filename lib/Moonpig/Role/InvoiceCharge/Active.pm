package Moonpig::Role::InvoiceCharge::Active;
use Moose::Role;
with(
  'Moonpig::Role::InvoiceCharge',
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

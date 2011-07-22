package Moonpig::Role::InvoiceCharge;
use Moose::Role;
with(
  'Moonpig::Role::Charge',
  'Moonpig::Role::HandlesEvents',
);

use namespace::autoclean;
use Moonpig::Behavior::EventHandlers;

implicit_event_handlers {
  return {
    'paid' => {
      'default' => Moonpig::Events::Handler::Noop->new,
    },
  }
};

1;

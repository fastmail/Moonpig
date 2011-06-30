package Moonpig::Role::InvoiceCharge;
use Moose::Role;
with(
  'Moonpig::Role::Charge',
  'Moonpig::Role::Charge::HandlesEvents',
);

use namespace::autoclean;

implicit_event_handlers {
  return {
    'paid' => {
      'default' => Moonpig::Events::Handler::Noop->new,
    },
  }
};

1;

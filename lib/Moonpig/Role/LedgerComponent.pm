package Moonpig::Role::LedgerComponent;
# ABSTRACT: something that's part of a ledger and links back to it
use Moose::Role;

with(
  'Moonpig::Role::HandlesEvents',
);

use Moonpig::Types qw(Ledger);

use Moonpig::Behavior::EventHandlers;

use namespace::autoclean;

has ledger => (
  is   => 'ro',
  isa  => Ledger,
  required => 1,
  weak_ref => 1,
  handles => [ qw(accountant) ],
);

implicit_event_handlers {
  return { created => { noop => Moonpig::Events::Handler::Noop->new } };
};

1;

package t::lib::Class::Ledger::ImplicitEvents;
use Moose;
extends 'Moonpig::Ledger::Basic';
with 't::lib::Factory::EventHandler';

use Moonpig::Types qw(EventHandler);

use Moonpig::Behavior::EventHandlers;

has noop_h => (
  is       => 'ro',
  isa      => EventHandler,
  init_arg => undef,
  default  => sub { $_[0]->make_event_handler(Noop => { }) },
);

has code_h => (
  is       => 'ro',
  isa      => EventHandler,
  init_arg => undef,
  default  => sub { $_[0]->make_event_handler('t::Test'); },
);

implicit_event_handlers {
  my ($self) = @_;

  return {
    'test.noop' => { nothing  => $self->noop_h },
    'test.code' => { callback => $self->code_h },
    'test.both' => { nothing  => $self->noop_h, callback => $self->code_h },
  };
};

1;

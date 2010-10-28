package Moonpig::Role::EventHandler;
use Moose::Role;

use Moonpig::Types qw(EventHandlerName);

use namespace::autoclean;

has implicit => (
  isa => 'Bool',
  traits  => [ 'Bool' ],
  default => 0,
  reader  => 'is_implicit',
  handles => {
    mark_implicit => 'set',
    is_explicit   => 'not',
  },
);

requires 'handle_event';

1;

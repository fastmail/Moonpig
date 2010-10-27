package Moonpig::Role::EventHandler;
use Moose::Role;

use Moonpig::Types qw(EventHandlerName);

use namespace::autoclean;

has name => (
  is  => 'ro',
  isa => EventHandlerName,
  required => 1,
);

requires 'handle_event';

1;

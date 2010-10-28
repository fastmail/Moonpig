package Moonpig::Role::EventHandler;
use Moose::Role;

use Moonpig::Types qw(EventHandlerName);

use namespace::autoclean;

requires 'handle_event';

1;

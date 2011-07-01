package Moonpig::Role::Consumer::Dummy;
# ABSTRACT: a minimal consumer for testing

use Carp qw(confess croak);
use Moonpig;
use Moonpig::Events::Handler::Method;
use Moonpig::Util qw(days event);
use Moose::Role;
use MooseX::Types::Moose qw(Num);

use Moonpig::Logger '$Logger';

with(
  'Moonpig::Role::Consumer',
  'Moonpig::Role::HandlesEvents',
  'Moonpig::Role::StubBuild',
);

use Moonpig::Behavior::EventHandlers;

use namespace::autoclean;

implicit_event_handlers {
  return {
    heartbeat => { },
  };
};

1;

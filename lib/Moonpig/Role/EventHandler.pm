package Moonpig::Role::EventHandler;
# ABSTRACT: a little helper object to which events are sent by their receivers

use Moose::Role;

use Moonpig::Types qw(EventHandlerName);

use Stick::Types qw(StickBool);
use Stick::Util qw(true false);

use namespace::autoclean;

has implicit => (
  isa => StickBool,
  coerce  => 1,
  default => 0,
  reader  => 'is_implicit',
  writer  => '__set_implicit',
);

sub mark_implicit { $_[0]->__set_implicit( true ) };
sub is_explicit   { ! $_[0]->is_implicit };

requires 'handle_event';

1;

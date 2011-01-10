package Moonpig::Events::Event;
# ABSTRACT: an event fired by one object for another to consume
use Moose;

use Moonpig::Types qw(EventName);

use namespace::autoclean;

with(
  'Moonpig::Role::Happening',
);

has '+ident' => (
  isa => EventName,
);

1;

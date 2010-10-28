package Moonpig::Events::Event;
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

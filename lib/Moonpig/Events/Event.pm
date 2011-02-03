package Moonpig::Events::Event;
# ABSTRACT: an event fired by one object for another to consume
use Moose;

# We had to make this a class, rather than a role, to +attr ident.  If we
# really want, in the future, we can convert Notification into a parameterized
# role. -- rjbs, 2011-01-12

use Moonpig::Types qw(EventName);

use namespace::autoclean;

with(
  'Moonpig::Role::Notification',
);

has '+ident' => (
  isa => EventName,
);

1;

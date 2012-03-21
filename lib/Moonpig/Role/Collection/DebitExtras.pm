package Moonpig::Role::Collection::DebitExtras;
use Class::MOP;
use Moose::Role;
use MooseX::Types::Moose qw(Num);
use Moonpig::Util qw(cents class);
use Stick::Publisher 0.20110324;
use Stick::Publisher::Publish 0.20110504;

sub add {
  # We need to sort out just what these collections are meant to do, then make
  # all our collections comply. -- rjbs, 2012-03-21
  confess "this method exists only to fulfill the role";
}

1;


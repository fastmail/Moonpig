package Moonpig::Role::CanExpire;
# ABSTRACT: something that can expire
use Moose::Role;

use Moonpig::Trait::Copy;
use Stick::Types qw(StickBool);
use Stick::Util qw(true false);

use namespace::autoclean;

has expired => (
  is  => 'ro',
  isa => StickBool,
  coerce  => 1,
  default => 0,
  reader  => 'is_expired',
  writer  => '__set_expired',
  traits  => [ qw(Copy) ],
);

sub expire { $_[0]->__set_expired( true ) }

1;

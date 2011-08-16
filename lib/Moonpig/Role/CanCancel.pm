package Moonpig::Role::CanCancel;
# ABSTRACT: something that can be canceled
use Moose::Role;

use Moonpig::Trait::Copy;
use Stick::Types qw(StickBool);
use Stick::Util qw(true false);

use namespace::autoclean;

has canceled => (
  is  => 'ro',
  isa => StickBool,
  coerce  => 1,
  default => 0,
  reader  => 'is_canceled',
  writer  => '__set_canceled',
  traits  => [ qw(Copy) ],
);

sub cancel { $_[0]->__set_canceled( true ) }

1;

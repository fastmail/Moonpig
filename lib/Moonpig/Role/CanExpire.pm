package Moonpig::Role::CanExpire;
# ABSTRACT: something that can expire

use Moose::Role;

use Moonpig::Behavior::Packable;

use Moonpig::Trait::Copy;
use Moonpig::Types qw(Time);
use Stick::Util qw(true false);

use namespace::autoclean;

has expired_at => (
  isa => Time,
  reader    => 'expired_at',
  predicate => 'is_expired',
  writer    => '__set_expired_at',
  traits    => [ qw(Copy SetOnce) ],
);

sub expire { $_[0]->__set_expired_at( Moonpig->env->now ) }

PARTIAL_PACK {
  return { $_[0]->expired_at ? (expired_at => $_[0]->expired_at) : () };
};

1;

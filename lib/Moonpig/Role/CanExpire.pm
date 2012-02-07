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
  # XXX Should be SetOnce, but this exposes a bug in ChargesPeriodically 2012-01-24 mjd
);

sub expire { $_[0]->__set_expired_at( Moonpig->env->now ) }

PARTIAL_PACK {
  return { $_[0]->expired_at ? (expired_at => $_[0]->expired_at) : () };
};

1;

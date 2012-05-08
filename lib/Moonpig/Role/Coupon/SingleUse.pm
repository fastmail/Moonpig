package Moonpig::Role::Coupon::SingleUse;
# ABSTRACT: a coupon that can be used only once

use Moonpig::Types qw(Time);
use Moose::Role;

use namespace::autoclean;

with (qw(Moonpig::Role::Coupon));

has applied_at => (
  is => 'ro',
  isa => Time,
  init_arg  => undef,
  predicate => 'was_applied',
  writer    => '_set_applied_at',
);

after mark_applied => sub {
  $_[0]->_set_applied_at( Moonpig->env->now );
};

around is_expired => sub {
  my $orig = shift;
  my $self = shift;
  return $self->was_applied || $self->$orig(@_);
};

1;

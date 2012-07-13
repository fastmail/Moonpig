package Moonpig::Role::LineItem::Abandonable;
use Moose::Role;
# ABSTRACT: a line item we might scratch out later

with(
  'Moonpig::Role::LineItem',
);

use namespace::autoclean;
use Moonpig::Behavior::Packable;
use Moonpig::Types qw(Time);
use MooseX::SetOnce;

has abandoned_at => (
  is => 'ro',
  isa => Time,
  predicate => 'is_abandoned',
  writer    => '__set_abandoned_at',
  traits => [ qw(SetOnce) ],
);

sub mark_abandoned {
  my ($self) = @_;
  Moonpig::X->throw("can't abandon an executed charge") if $self->is_executed;
  $self->__set_abandoned_at( Moonpig->env->now );
}

PARTIAL_PACK {
  my ($self) = @_;

  return {
    abandoned_at => $self->abandoned_at,
  };
};

1;

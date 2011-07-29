package Moonpig::Role::Coupon::SingleUse;
# ABSTRACT: a coupon that can be used only once

use MooseX::Types::Moose qw(Bool);
use Moose::Role;

with (qw(Moonpig::Role::Coupon));

has already_used => (
  is => 'rw',
  isa => Bool,
  default => 0,
);

sub use_up {
  $_[0]->already_used(1);
}

sub applied {
  $_[0]->use_up;
}

around is_expired => sub {
  my $orig = shift;
  my $self = shift;
  return $self->already_used || $self->$orig(@_);
};

1;

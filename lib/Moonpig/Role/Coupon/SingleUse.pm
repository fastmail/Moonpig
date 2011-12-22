package Moonpig::Role::Coupon::SingleUse;
# ABSTRACT: a coupon that can be used only once

use Stick::Types qw(StickBool);
use Moose::Role;

with (qw(Moonpig::Role::Coupon));

has was_applied => (
  is => 'rw',
  isa => StickBool,
  default => 0,
);

sub mark_applied {
  $_[0]->was_applied(1);
}

around is_expired => sub {
  my $orig = shift;
  my $self = shift;
  return $self->was_applied || $self->$orig(@_);
};

1;

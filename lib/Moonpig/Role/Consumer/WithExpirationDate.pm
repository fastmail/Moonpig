package Moonpig::Role::Consumer::WithExpirationDate;
# ABSTRACT: a consumer with a specified expire date that does not have
# a replacement

use Carp qw(confess croak);
use Moose::Role;
use Moonpig;
use Moonpig::Behavior::EventHandlers;
use Moonpig::Events::Handler::Method;
use Moonpig::Types qw(Time);
use Moonpig::URI;
use namespace::autoclean;
use strict;

with (
  'Moonpig::Role::Consumer',
  'Moonpig::Role::HandlesEvents',
  'Moonpig::Role::StubBuild',
);

has +replacement_mri => (
  is => 'ro',
  init_arg => undef,
  default => sub { Moonpig::URI->nothing },
);

has expire_date => (
  is => 'ro',
  isa => Time,
  required => 1,
);

implicit_event_handlers {
  return {
    heartbeat => {
      check_expiry => Moonpig::Events::Handler::Method->new('check_expiry'),
    },
  };
};

sub check_expiry {
  my ($self, $event, $arg) = @_;
  if ($event->payload->{timestamp} >= $self->expire_date) {
    $self->expire;
  }
}

1;

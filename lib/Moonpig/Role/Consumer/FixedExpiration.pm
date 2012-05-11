package Moonpig::Role::Consumer::FixedExpiration;
# ABSTRACT: a consumer that expires automatically on a particular date
use Moose::Role;

use MooseX::Types::Moose qw(Str);
use Moonpig::Types qw(PositiveMillicents Time);

with(
  'Moonpig::Role::Consumer',
  'Moonpig::Role::Consumer::PredictsExpiration',
);

use namespace::autoclean;

use Moonpig::Behavior::EventHandlers;

implicit_event_handlers {
  return {
    heartbeat => {
      charge => Moonpig::Events::Handler::Method->new(
        method_name => '_check_expiry',
      ),
    },
  };
};

sub expiration_date;
has expiration_date => (
  is  => 'ro',
  isa => Time,
  required => 1,
);

sub _check_expiry {
  my ($self) = @_;
  return if $self->is_expired;
  $self->expire if $self->expiration_date <= Moonpig->env->now;
}

sub remaining_life {
  my ($self, $when) = @_;
  $when ||= Moonpig->env->now;
  my $diff = $self->expiration_date - $when;
  return $diff < 0 ? 0 : $diff;
}

sub estimated_lifetime {
  my ($self) = @_;
  return $self->expiration_date - $self->activated_at;
}

1;

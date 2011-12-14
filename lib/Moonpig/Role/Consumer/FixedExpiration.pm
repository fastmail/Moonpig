package Moonpig::Role::Consumer::FixedExpiration;
# ABSTRACT: a consumer that expires automatically on a particular date
use Moose::Role;

use MooseX::Types::Moose qw(Str);
use Moonpig::Types qw(PositiveMillicents Time);

with(
  'Moonpig::Role::Consumer',
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

# name taken from similar method in ByTime consumer
has expire_date => (
  is  => 'rw',
  isa => Time,
  required => 1,
);

sub _check_expiry {
  my ($self) = @_;
  $self->expire if $self->expire_date <= Moonpig->env->now;
}

sub remaining_life {
  my ($self, $when) = @_;
  $when ||= Moonpig->env->now;
  my $diff = $self->expire_date - $when;
  return $diff < 0 ? 0 : $diff;
}

1;

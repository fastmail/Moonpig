package Moonpig::Role::Env::WithMockedTime;
# ABSTRACT: a testing environment that has a fake, mutable clock

use Moose::Role;
with 'Moonpig::Role::Env';

use Moonpig::Types qw(Time);
use Moose::Util::TypeConstraints;

use namespace::autoclean;

has _clock_state => (
  is => 'rw',
  isa => enum([ qw(wallclock stopped offset) ]),
  init_arg => undef,
  default  => 'wallclock',
);

has _clock_stopped_time => (
  is  => 'rw',
  isa => Time,
);

has _clock_restarted_at => (
  is  => 'rw',
  isa => 'Int', # epoch seconds
);

sub stop_clock {
  my ($self) = @_;

  my $now = $self->now;
  $self->_clock_stopped_time( $now );
  $self->_clock_state('stopped');

  return $now;
}

sub elapse_time {
  my ($self, $duration) = @_;

  Moonpig::X->throw("can't elapse time when clock is not stopped")
    if $self->_clock_state ne 'stopped';

  $duration = DateTime::Duration->new(seconds => $duration)
    unless ref $duration;

  Moonpig::X->throw("tried to elapse negative time")
    if $duration->is_negative;

  $self->_clock_stopped_time( $self->now->add_duration( $duration ) );
}

sub stop_clock_at {
  my ($self, $time) = @_;

  $self->_clock_state('stopped');
  $self->_clock_stopped_time( $time );

  return $time;
}

sub restart_clock {
  my ($self) = @_;

  # if the clock is already running, just let it keep running
  return if $self->_clock_state =~ /\A(?:wallclock|offset)\z/;

  $self->_clock_restarted_at(time);
  $self->_clock_state('offset');
  return;
}

sub reset_clock {
  my ($self) = @_;
  $self->_clock_state('wallclock');
  return;
}

sub now {
  my ($self) = @_;

  my $state = $self->_clock_state;

  return Moonpig::DateTime->now if $state eq 'wallclock';
  return $self->_clock_stopped_time if $state eq 'stopped';

  return $self->_clock_stopped_time + (time - $self->_clock_restarted_at)
    if $state eq 'offset';

  confess "Bizarre clock state '$state'; aborting";
}

# Env->clock_offset = Env->now - true_current_time()
sub clock_offset {
  my ($self) = @_;

  my $state = $self->_clock_state;
  if ($state eq 'wallclock') {
    return 0;
  } elsif ($state eq 'stopped') {
    return $self->_clock_stopped_time - Moonpig::DateTime->now;
  } elsif ($state eq 'offset') {
    return $self->_clock_stopped_time - $self->_clock_restarted_at;
  }

  confess "Bizarre clock state '$state'; aborting";
}

1;

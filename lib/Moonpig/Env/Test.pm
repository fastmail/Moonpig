package Moonpig::Env::Test;
use Moose;
with 'Moonpig::Role::Env';

Moonpig->set_env( __PACKAGE__->new );

use Email::Sender::Transport::Test;
use Moonpig::X;
use Moonpig::Events::Handler::Code;

has email_sender => (
  is   => 'ro',
  does => 'Email::Sender::Transport',
  default => sub { Email::Sender::Transport::Test->new },
);

sub handle_send_email {
  my ($self, $event, $arg) = @_;

  # XXX: validate email -- rjbs, 2010-12-08

  $self->email_sender->send_email($arg->{email}, $arg->{env});
}

has current_time => (
  is  => 'rw',
  isa => 'Moonpig::DateTime',
  predicate => 'time_stopped',
);

before current_time => sub {
  my $self = shift;
  return unless @_;

  Moonpig::X->throw("can't reverse time")
    if $self->time_stopped and $_[0] < $self->current_time;
};

sub stop_time {
  my ($self) = @_;

  Moonpig::X->throw("can't stop time twice") if $self->time_stopped;

  $self->current_time( Moonpig::DateTime->new );
}

sub elapse_time {
  my ($self, $duration) = @_;

  $duration = DateTime::Duration->new(seconds => $duration)
    unless ref $duration;

  Moonpig::X->throw("tried to elapse negative time")
    if $duration->is_negative;

  $self->current_time( $self->now->add_duration( $duration ) );
}

sub now {
  my ($self) = @_;
  return $self->time_stopped ? $self->current_time
    : Moonpig::DateTime->now();
}

1;

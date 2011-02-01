package Moonpig::Env::Test;
# ABSTRACT: a testing environment for Moonpig

use Moose;
with 'Moonpig::Role::Env';

use namespace::autoclean;

# BEGIN HUGE AWFUL HACK -- rjbs, 2010-12-16
$ENV{MOONPIG_MKITS_DIR} = 'share/kit';
use File::ShareDir;
BEGIN {
  my $orig = File::ShareDir->can('dist_dir');
  Sub::Install::reinstall_sub({
    into => 'File::ShareDir',
    as   => 'dist_dir',
    code => sub {
      return 'share' if $_[0] eq 'Moonpig';
      return $orig->(@_);
    },
  });
}
# END HUGE AWFUL HACK -- rjbs, 2010-12-16

use Email::Sender::Transport::Test;
use Moonpig::X;
use Moonpig::DateTime;
use Moonpig::Events::Handler::Code;
use Moonpig::Types qw(Time);

use Moose::Util::TypeConstraints;

has email_sender => (
  is   => 'ro',
  does => 'Email::Sender::Transport',
  default => sub { Email::Sender::Transport::Test->new },
);

sub handle_send_email {
  my ($self, $event, $arg) = @_;

  # XXX: validate email -- rjbs, 2010-12-08

  my $sender = $self->email_sender;

  $self->email_sender->send_email(
    $event->payload->{email},
    $event->payload->{env},
  );
}

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

  Moonpig::X->throw("can't stop clock twice")
    if $self->_clock_state eq 'stopped';

  $self->_clock_stopped_time( Moonpig::DateTime->now );
  $self->_clock_state('stopped');

  return;
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

sub now {
  my ($self) = @_;

  my $state = $self->_clock_state;

  return Moonpig::DateTime->now if $state eq 'wallclock';
  return $self->_clock_stopped_time if $state eq 'stopped';

  return $self->_clock_stopped_time + (time - $self->_clock_restarted_at)
    if $state eq 'offset';

  ...
}

sub stop_clock_at {
  my ($self, $time) = @_;

  Time->assert_valid($time);

  $self->_clock_state('stopped');
  $self->_clock_stopped_time( $time );
}

has _guid_serial_number_registry => (
  is  => 'ro',
  init_arg => undef,
  default  => sub {  {}  },
);

my $i = 1;

sub format_guid {
  my ($self, $guid) = @_;
  my $reg = $self->_guid_serial_number_registry;
  return ($reg->{ $guid } ||= $i++)
}

Moonpig->set_env( __PACKAGE__->new );

1;

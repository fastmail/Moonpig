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

has _current_time => (
  is  => 'rw',
  isa => 'Moonpig::DateTime',
  predicate => 'time_stopped',
);

sub stop_time {
  my ($self) = @_;

  Moonpig::X->throw("can't stop time twice") if $self->time_stopped;

  $self->_current_time( Moonpig::DateTime->now );
}

sub elapse_time {
  my ($self, $duration) = @_;

  $duration = DateTime::Duration->new(seconds => $duration)
    unless ref $duration;

  Moonpig::X->throw("tried to elapse negative time")
    if $duration->is_negative;

  $self->_current_time( $self->now->add_duration( $duration ) );
}

sub now {
  my ($self) = @_;
  return $self->time_stopped ? $self->_current_time
    : Moonpig::DateTime->now();
}

sub current_time {
  my ($self, $new) = @_;
  return @_ > 1 ? $self->_current_time($new) : $self->now();
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

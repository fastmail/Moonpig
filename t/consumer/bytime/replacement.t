use strict;
use warnings;

use Carp qw(confess croak);
use DateTime;
use Moonpig::Consumer::ByTime;
use Moonpig::Events::Handler::Code;
use Moonpig::Util -all;
use Test::More;
use Test::Routine::Util;
use Test::Routine;

my $CLASS = "Moonpig::Consumer::ByTime";

# to do:
#  normal behavior without successor: setup replacement
#  missed heartbeat
#  extra heartbeat

has ledger => (
  is => 'rw',
  isa => 'Moonpig::Role::Ledger',
  default => sub { $_[0]->test_ledger() },
);
sub ledger;  # Work around bug in Moose 'requires';

with ('t::lib::Factory::Consumers',
      't::lib::Factory::Ledger',
     );

sub queue_handler {
  my ($name, $queue) = @_;
  $queue ||= [];
  return Moonpig::Events::Handler::Code->new(
    code => sub {
      my ($receiver, $event, $args, $handler) = @_;
      push @$queue, [ $receiver, $event->ident, $event->payload ];
    },
   );
}

test "with_successor" => sub {
  my ($self) = @_;

  my @eq;

  plan tests => 2;
  $self->ledger->register_event_handler(
    'contact-humans', 'noname', queue_handler("ld", \@eq)
   );

  # Pretend today is 2000-01-01 for convenience
  my $jan1 = DateTime->new( year => 2000, month => 1, day => 1 );

  for my $test (
    [ 'normal', [ 1 .. 31 ] ],  # one per day like it should be
    [ 'double', [ map( ($_,$_), 1 .. 31) ] ], # each one delivered twice
## TODO TEST
##    [ 'missed a', [ 29, 30, 31 ], 2 ], # Jan 24 warning delivered on 29th
   ) {
    my ($name, $schedule, $n_warnings) = @$test;

    # Normally we get 5 warnings, when the account is 28, 21, 14, 7 ,
    # or 1 day from termination.  (On Jan 3, 10, 17, 24, and 30.)  But
    # if heartbeats are skipped, we might miss some
    $n_warnings = 5 unless defined $n_warnings;

    my $b = Moonpig::Bank::Basic->new({
      ledger => $self->ledger,
      amount => dollars(31),	# One dollar per day for rest of January
    });

    my $c = $self->test_consumer_pair(
      $CLASS, {
        ledger => $self->ledger,
        bank => $b,
        old_age => DateTime::Duration->new( years => 1000 ),
        current_time => $jan1,
      });

    for my $day (@$schedule) {
      my $beat_time = DateTime->new( year => 2000, month => 1, day => $day );
      $c->handle_event(event('heartbeat', { datetime => $beat_time }));
    }
    is(@eq, $n_warnings,
       "received $n_warnings warnings (schedule '$name')");
    @eq = ();
  }
};

test "without_successor" => sub {
  # A consumer with no successor will create and install one,
  # then hand off control to it
  pass();
};


run_me;
done_testing;

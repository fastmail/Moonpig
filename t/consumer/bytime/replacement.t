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

with 't::lib::Factory::Consumers';

# to do:
#  normal behavior without successor: setup replacement
#  missed heartbeat
#  extra heartbeat

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
  my $ld = $self->test_ledger;
  $ld->register_event_handler(
    'contact-humans', 'noname', queue_handler("ld", \@eq)
   );

  # Pretend today is 2000-01-01 for convenience
  my $jan1 = DateTime->new( year => 2000, month => 1, day => 1 );

  for my $repeated_heartbeats (0, 1) {

    my $b = Moonpig::Bank::Basic->new({
      ledger => $ld,
      amount => dollars(31),	# One dollar per day for rest of January
    });


    my $c = $self->test_consumer_pair(
      $CLASS, {
        ledger => $ld,
        bank => $b,
        old_age => DateTime::Duration->new( years => 1000 ),
        current_time => $jan1,
      });

    for my $day (1..31) {
      my $beat_time = DateTime->new( year => 2000, month => 1, day => $day );
      $c->handle_event(event('heartbeat', { datetime => $beat_time }));
      $c->handle_event(event('heartbeat', { datetime => $beat_time }))
        if $repeated_heartbeats;
    }
    is(@eq, 5,
       "received five warnings (repeated heartbeats = $repeated_heartbeats");
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

use strict;
use warnings;

use Carp qw(confess croak);
use DateTime;
use Test::Routine;
use Test::More;
use Test::Routine::Util;
use Moonpig::Consumer::ByTime;
use Moonpig::Events::Handler::Code;
use Moonpig::Util -all;

with 't::lib::Factory::Ledger';

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

  plan tests => 1;
  my $ld = $self->test_ledger;
  my @eq;
  $ld->register_event_handler(
    'contact-humans', 'noname', queue_handler("ld", \@eq)
   );

  # Pretend today is 2000-01-01 for convenience
  my $today = DateTime->new( year => 2000, month => 1, day => 1 );

  my ($c0, $c1);   # $c0 is active, $c1 is successor

  my $b = Moonpig::Bank::Basic->new({
    ledger => $ld,
    amount => dollars(31),	# One dollar per day for rest of January
   });


  $c0 = Moonpig::Consumer::ByTime->new({
    ledger => $ld,
    bank => $b,
    cost_amount => dollars(1),
    cost_period => DateTime::Duration->new( days => 1 ),
    old_age => DateTime::Duration->new( years => 1000 ),
    current_time => $today,
  });

  $c1 =  Moonpig::Consumer::ByTime->new({
    ledger => $ld,
    cost_amount => dollars(1),
    cost_period => DateTime::Duration->new( days => 1 ),
    old_age => DateTime::Duration->new( years => 1000 ),
    current_time => $today,
  });
  $c0->replacement($c1);

  for my $day (1..31) {
    my $beat_time = DateTime->new( year => 2000, month => 1, day => $day );
    $c0->handle_event(event('heartbeat', { datetime => $beat_time }));
  }
  is(@eq, 5, "received five warnings");
};

run_me;
done_testing;

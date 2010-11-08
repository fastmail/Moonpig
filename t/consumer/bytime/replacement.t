use strict;
use warnings;

use Carp qw(confess croak);
use DateTime;
use Moonpig::Consumer::ByTime;
use Moonpig::Events::Handler::Code;
use Moonpig::Events::Handler::Noop;
use Moonpig::URI;
use Moonpig::Util -all;
use Test::More;
use Test::Routine::Util;
use Test::Routine;

my $CLASS = "Moonpig::Consumer::ByTime";

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

  plan tests => 3;
  $self->ledger($self->test_ledger);
  $self->ledger->register_event_handler(
    'contact-humans', 'noname', queue_handler("ld", \@eq)
  );

  # Pretend today is 2000-01-01 for convenience
  my $jan1 = Moonpig::DateTime->new( year => 2000, month => 1, day => 1 );

  for my $test (
    [ 'normal', [ 1 .. 31 ] ],  # one per day like it should be
    [ 'double', [ map( ($_,$_), 1 .. 31) ] ], # each one delivered twice
    [ 'missed', [ 29, 30, 31 ], 2 ], # Jan 24 warning delivered on 29th
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
        old_age => years(1000),
        current_time => $jan1,
      });

    for my $day (@$schedule) {
      my $tick_time = Moonpig::DateTime->new(
        year => 2000, month => 1, day => $day
      );
      $c->handle_event(event('heartbeat', { datetime => $tick_time }));
    }
    is(@eq, $n_warnings,
       "received $n_warnings warnings (schedule '$name')");
    @eq = ();
  }
};

# We'll have one consumer which, when it reaches its low funds point,
# will create a replacement consumer, which should start hollering.
test "without_successor" => sub {
  my ($self) = @_;

  $self->ledger($self->test_ledger);
  $self->ledger->register_event_handler(
    'contact-humans', 'noname', Moonpig::Events::Handler::Noop->new()
  );

  plan tests => 4 * 3;

  # Pretend today is 2000-01-01 for convenience
  my $jan1 = Moonpig::DateTime->new( year => 2000, month => 1, day => 1 );
  my $mri =
    Moonpig::URI->new("moonpig://test/method?method=construct_replacement");

  for my $test (
    [ 'normal', [ 1 .. 31 ] ],  # one per day like it should be
    [ 'double', [ map( ($_,$_), 1 .. 31) ] ], # each one delivered twice
    [ 'missed', [ 29, 30, 31 ], "2000-01-29" ], # successor delayed until 29th
   ) {
    my ($name, $schedule, $succ_creation_date) = @$test;
    $succ_creation_date ||= "2000-01-12"; # Should be created on Jan 12

    my $b = Moonpig::Bank::Basic->new({
      ledger => $self->ledger,
      amount => dollars(31),	# One dollar per day for rest of January
    });

    my $c = $self->test_consumer(
      $CLASS, {
        ledger => $self->ledger,
        bank => $b,
        old_age => days(20),
        current_time => $jan1,
        replacement_mri => $mri,
      });

    my @eq;
    $c->register_event_handler(
      'consumer-create-replacement', 'noname', queue_handler("ld", \@eq)
    );
    for my $day (@$schedule) {
      my $tick_time = Moonpig::DateTime->new(
        year => 2000, month => 1, day => $day
      );
      $c->handle_event(event('heartbeat', { datetime => $tick_time }));
    }

    is(@eq, 1, "received one request to create replacement (schedule '$name')");
    my (undef, $ident, $payload) = @{$eq[0] || [undef, undef, {}]};
    is($ident, 'consumer-create-replacement', "event name");
    is($payload->{timestamp}->ymd, $succ_creation_date, "event date");
    is($payload->{mri}, $mri,  "event MRI");
  }
};

test "irreplaceable" => sub {
  # this consumer has been instructed not to generate a replacement for itself
  pass();
};

run_me;
done_testing;

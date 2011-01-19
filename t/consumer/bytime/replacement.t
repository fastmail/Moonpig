use strict;
use warnings;

use Carp qw(confess croak);
use Moonpig::Events::Handler::Code;
use Moonpig::Events::Handler::Noop;
use Moonpig::URI;
use Moonpig::Util -all;
use Test::More;
use Test::Routine::Util;
use Test::Routine;

use t::lib::Logger;

use Moonpig::Env::Test;

my $CLASS = class('Consumer::ByTime');

has ledger => (
  is   => 'rw',
  does => 'Moonpig::Role::Ledger',
);
sub ledger;  # Work around bug in Moose 'requires';

with ('t::lib::Factory::Consumers',
      't::lib::Factory::Ledger',
     );

before run_test => sub {
  Moonpig->env->email_sender->clear_deliveries;
};

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

  plan tests => 9;

  for my $test (
    [ 'double', [ map( ($_,$_), 1 .. 31) ] ], # each one delivered twice
    [ 'missed', [ 29, 30, 31 ], 2 ], # Jan 24 warning delivered on 29th
    [ 'normal', [ 1 .. 31 ] ],  # one per day like it should be
  ) {

    # Pretend today is 2000-01-01 for convenience
    my $jan1 = Moonpig::DateTime->new( year => 2000, month => 1, day => 1 );
    Moonpig->env->current_time($jan1);

    $self->ledger($self->test_ledger);

    my ($name, $schedule, $n_warnings) = @$test;

    # XXX THIS WILL CHANGE AS DUNNING / GRACE BEHAVIOR IS REFINED
    # Normally we get 8 requests for payment:
    #  * 1 when the consumer is first created
    #  * 1 every 4 days thereafter: the 4th, 8th, 12th, 16th, 20th, 24th, 28th
    $n_warnings = 8 unless defined $n_warnings;

    my $b = class('Bank')->new({
      ledger => $self->ledger,
      amount => dollars(31),	# One dollar per day for rest of January
    });

    my $c = $self->test_consumer_pair(
      $CLASS,
      {
        ledger  => $self->ledger,
        bank    => $b,
        old_age => years(1000),
      },
    );

    {
      my @deliveries = Moonpig->env->email_sender->deliveries;
      is(@deliveries, 0, "no notices sent yet");
    }

    $self->ledger->handle_event(event('heartbeat'));

    {
      my @deliveries = Moonpig->env->email_sender->deliveries;
      is(@deliveries, 1, "initial invoice sent");
    }

    for my $day (@$schedule) {
      my $tick_time = Moonpig::DateTime->new(
        year => 2000, month => 1, day => $day
      );

      Moonpig->env->current_time($tick_time);
      $self->ledger->handle_event(event('heartbeat'));
    }

    my @deliveries = Moonpig->env->email_sender->deliveries;
    is(@deliveries, $n_warnings,
       "received $n_warnings warnings (schedule '$name')");
    Moonpig->env->email_sender->clear_deliveries;
  }
};

# We'll have one consumer which, when it reaches its low funds point,
# will create a replacement consumer, which should start hollering.
test "without_successor" => sub {
  my ($self) = @_;

  # Pretend today is 2000-01-01 for convenience
  my $jan1 = Moonpig::DateTime->new( year => 2000, month => 1, day => 1 );
  Moonpig->env->current_time($jan1);

  $self->ledger($self->test_ledger);
  $self->ledger->register_event_handler(
    'contact-humans', 'default', Moonpig::Events::Handler::Noop->new()
  );

  plan tests => 4 * 3;

  my $mri =
    Moonpig::URI->new("moonpig://test/method?method=construct_replacement");

  for my $test (
    [ 'normal', [ 1 .. 31 ] ],  # one per day like it should be
    [ 'double', [ map( ($_,$_), 1 .. 31) ] ], # each one delivered twice
    [ 'missed', [ 29, 30, 31 ], "2000-01-29" ], # successor delayed until 29th
   ) {
    my ($name, $schedule, $succ_creation_date) = @$test;
    $succ_creation_date ||= "2000-01-12"; # Should be created on Jan 12
    Moonpig->env->current_time($jan1);

    my $b = class('Bank')->new({
      ledger => $self->ledger,
      amount => dollars(31),	# One dollar per day for rest of January
    });

    my $c = $self->test_consumer(
      $CLASS, {
        ledger => $self->ledger,
        bank => $b,
        old_age => days(20),
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
      Moonpig->env->current_time($tick_time);
      $self->ledger->handle_event(event('heartbeat', { timestamp => $tick_time }));
    }

    is(@eq, 1, "received one request to create replacement (schedule '$name')");
    my (undef, $ident, $payload) = @{$eq[0] || [undef, undef, {}]};
    is($ident, 'consumer-create-replacement', "event name");
    is($payload->{timestamp}->ymd, $succ_creation_date, "event date");
    is($payload->{mri}, $mri,  "event MRI");
  }
};

test "irreplaceable" => sub {
  my ($self) = @_;
  $self->ledger($self->test_ledger);
  plan tests => 3;

  # Pretend today is 2000-01-01 for convenience
  my $jan1 = Moonpig::DateTime->new( year => 2000, month => 1, day => 1 );

  for my $test (
    [ 'normal', [ 1 .. 31 ] ],  # one per day like it should be
    [ 'double', [ map( ($_,$_), 1 .. 31) ] ], # each one delivered twice
    [ 'missed', [ 29, 30, 31 ] ], # successor delayed until 29th
   ) {
    my ($name, $schedule) = @$test;
    note("testing schedule '$name'");

    my $b = class('Bank')->new({
      ledger => $self->ledger,
      amount => dollars(10),	# Not enough to pay out the month
    });

    my $c = $self->test_consumer(
      $CLASS, {
        is_replaceable => 0,
        ledger => $self->ledger,
        bank => $b,
        old_age => days(20),
        replacement_mri => Moonpig::URI->nothing(),
      });

    for my $day (@$schedule) {
      my $tick_time = Moonpig::DateTime->new(
        year => 2000, month => 1, day => $day
      );
      $self->ledger->handle_event(event('heartbeat', { timestamp => $tick_time }));
    }
    pass();
  }
};

run_me;
done_testing;

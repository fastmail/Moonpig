use strict;
use warnings;

use Carp qw(confess croak);
use Data::GUID qw(guid_string);
use Moonpig::Events::Handler::Noop;
use Moonpig::Util -all;
use Test::More;
use Test::Routine::Util;
use Test::Routine;

use t::lib::TestEnv;

use t::lib::Logger;
use t::lib::Class::EventHandler::Test;
use Moonpig::Test::Factory qw(build);

use t::lib::TestEnv;

with(
  'Moonpig::Test::Role::UsesStorage',
 );

before run_test => sub {
  Moonpig->env->email_sender->clear_deliveries;
};

sub queue_handler {
  my ($name, $queue) = @_;
  $queue ||= [];
  return t::lib::Class::EventHandler::Test->new({ log => $queue });
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
    Moonpig->env->stop_clock_at($jan1);

    my $stuff;
    my $xid = "consumer:test:" . guid_string();
    Moonpig->env->storage->do_rw(sub {
      $stuff = build(
        initial => {
          class              => class('Consumer::ByTime::FixedCost'),
          bank               => dollars(31),
          old_age            => years(1000),
          charge_description => "test charge",
          cost_amount        => dollars(1),
          cost_period        => days(1),
          replacement        => 'replacement',
          replacement_plan   => [ get => '/nothing' ],
          xid                => $xid,
        },
        replacement => {
          class              => class('Consumer::ByTime::FixedCost'),
          old_age            => years(1000),
          charge_description => "test charge",
          cost_amount        => dollars(1),
          cost_period        => days(1),
          replacement_plan   => [ get => '/nothing' ],
          xid                => $xid,
        },
      );
      Moonpig->env->save_ledger($stuff->{ledger});
    });

    my ($name, $schedule, $n_warnings) = @$test;

    # XXX THIS WILL CHANGE AS DUNNING / GRACE BEHAVIOR IS REFINED
    # Normally we get 8 requests for payment:
    #  * 1 when the consumer is first created
    #  * 1 every 4 days thereafter: the 4th, 8th, 12th, 16th, 20th, 24th, 28th
    $n_warnings = 8 unless defined $n_warnings;

    {
      my @deliveries = Moonpig->env->email_sender->deliveries;
      is(@deliveries, 0, "no notices sent yet");
    }

    $self->heartbeat_and_send_mail($stuff->{ledger});

    {
      my @deliveries = Moonpig->env->email_sender->deliveries;
      is(@deliveries, 1, "initial invoice sent");
    }

    for my $day (@$schedule) {
      my $tick_time = Moonpig::DateTime->new(
        year => 2000, month => 1, day => $day
      );

      Moonpig->env->stop_clock_at($tick_time);
      $self->heartbeat_and_send_mail($stuff->{ledger});
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
  Moonpig->env->stop_clock_at($jan1);

  plan tests => 3 * 3;

  for my $test (
    [ 'normal', [ 1 .. 31 ] ],  # one per day like it should be
    [ 'double', [ map( ($_,$_), 1 .. 31) ] ], # each one delivered twice
    [ 'missed', [ 29, 30, 31 ], "2000-01-29" ], # successor delayed until 29th
   ) {
    my ($name, $schedule, $succ_creation_date) = @$test;
    $succ_creation_date ||= "2000-01-12"; # Should be created on Jan 12
    Moonpig->env->stop_clock_at($jan1);

    my $xid = "consumer:test:" . guid_string();
    my $stuff;
    Moonpig->env->storage->do_rw(sub {
      $stuff = build(
        consumer => {
          class              => class('Consumer::ByTime::FixedCost'),
          charge_description => "test charge",
          old_age            => days(20),
          replacement_plan   => [ get => 'template-like-this' ],
          cost_amount        => dollars(1),
          cost_period        => days(1),
          bank               => dollars(31),
          xid                => $xid,
        }
      );
      Moonpig->env->save_ledger($stuff->{ledger});
    });

    $stuff->{ledger}->register_event_handler(
      'contact-humans', 'default', Moonpig::Events::Handler::Noop->new()
     );

    my @eq;
    $stuff->{consumer}->register_event_handler(
      'consumer-create-replacement', 'noname', queue_handler("ld", \@eq)
    );
    for my $day (@$schedule) {
      my $tick_time = Moonpig::DateTime->new(
        year => 2000, month => 1, day => $day
      );
      Moonpig->env->stop_clock_at($tick_time);
      $self->heartbeat_and_send_mail(
        $stuff->{ledger},
        { timestamp => $tick_time },
      );
    }

    is(@eq, 1, "received one request to create replacement (schedule '$name')");
    my ($receiver, $event) = @{$eq[0] || [undef, undef]};
    is($event->ident, 'consumer-create-replacement', "event name");
    is($event->timestamp->ymd, $succ_creation_date, "event date");
  }
};

test "irreplaceable" => sub {
  my ($self) = @_;
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

    my $xid = "consumer:test:" . guid_string();
    my $stuff;
    Moonpig->env->storage->do_rw(sub {
      $stuff = build(
        consumer => {
          class              => class('Consumer::ByTime::FixedCost'),
          old_age            => days(20),
          cost_amount        => dollars(1),
          cost_period        => days(1),
          charge_description => "test charge",
          bank               => dollars(10),
          replacement_plan   => [ get => '/nothing' ],
          xid                => $xid,
        }
      );
      Moonpig->env->save_ledger($stuff->{ledger});
    });

    for my $day (@$schedule) {
      my $tick_time = Moonpig::DateTime->new(
        year => 2000, month => 1, day => $day
      );

      Moonpig->env->stop_clock_at($tick_time);
      $self->heartbeat_and_send_mail($stuff->{ledger});
    }
    pass();
  }
};

run_me;
done_testing;

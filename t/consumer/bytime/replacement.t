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
use t::lib::ConsumerTemplateSet::Test;
use t::lib::Logger;
use t::lib::Class::EventHandler::Test;
use Moonpig::Test::Factory qw(build do_with_fresh_ledger);

use t::lib::TestEnv;

with(
  'Moonpig::Test::Role::LedgerTester',
);

sub queue_handler {
  my ($name, $queue) = @_;
  $queue ||= [];
  return t::lib::Class::EventHandler::Test->new({ log => $queue });
}

test "with_successor" => sub {
  my ($self) = @_;

  plan tests => 3;

  for my $test (
    [ 'double', [ map( ($_,$_), 1 .. 31) ] ], # each one delivered twice
    [ 'missed', [ 29, 30, 31 ], 2 ], # Jan 24 message delivered on 29th
    [ 'normal', [ 1 .. 31 ] ],  # one per day like it should be
  ) {
    my ($name, $schedule, $n_messages) = @$test;

    subtest "heartbeat schedule: $name" => sub {
      # Pretend today is 2000-01-01 for convenience
      my $jan1 = Moonpig::DateTime->new( year => 2000, month => 1, day => 1 );
      Moonpig->env->stop_clock_at($jan1);

      my $stuff;
      my $xid = "consumer:test:" . guid_string();
      Moonpig->env->storage->do_rw(sub {
        $stuff = build(
          initial => {
            class              => class('Consumer::ByTime::FixedAmountCharge'),
            bank               => dollars(31),
            charge_description => "test charge",
            charge_amount      => dollars(1),
            cost_period        => days(1),
            replacement        => 'replacement',
            replacement_plan   => [ get => '/nothing' ],
            xid                => $xid,
          },
          replacement => {
            class              => class('Consumer::ByTime::FixedAmountCharge'),
            charge_description => "test charge",
            charge_amount      => dollars(1),
            cost_period        => days(1),
            replacement_plan   => [ get => '/nothing' ],
            xid                => $xid,
          },
        );
        Moonpig->env->save_ledger($stuff->{ledger});
      });

      # ATTENTION: THIS WILL CHANGE AS DUNNING / GRACE BEHAVIOR IS REFINED
      # Normally we get 8 requests for payment:
      #  * 1 when the consumer is first created
      #  * 1 every 4 days thereafter: the 4th, 8th, 12th, 16th, 20th, 24th, 28th
      $n_messages //= 8;

      {
        my @deliveries = $self->get_and_clear_deliveries;
        is(@deliveries, 0, "no notices sent yet");
      }

      $self->heartbeat_and_send_mail($stuff->{ledger});

      {
        my @deliveries = $self->get_and_clear_deliveries;
        is(@deliveries, 1, "initial invoice sent");
      }

      for my $day (@$schedule) {
        my $tick_time = Moonpig::DateTime->new(
          year => 2000, month => 1, day => $day
        );

        Moonpig->env->stop_clock_at($tick_time);
        $self->heartbeat_and_send_mail($stuff->{ledger});
      }

      my @deliveries = $self->get_and_clear_deliveries;
      is(1+@deliveries, $n_messages,
         "received $n_messages messages (schedule '$name')");
    };
  }
};

# We'll have one consumer which, when it reaches its low funds point,
# will create a replacement consumer, which should start hollering.
test "without_successor" => sub {
  my ($self) = @_;

  # Pretend today is 2000-01-01 for convenience
  my $jan1 = Moonpig::DateTime->new( year => 2000, month => 1, day => 1 );
  Moonpig->env->stop_clock_at($jan1);

  plan tests => 3;

  for my $test (
    [ 'normal', [ 1 .. 31 ] ],  # one per day like it should be
    [ 'double', [ map( ($_,$_), 1 .. 31) ] ], # each one delivered twice
    [ 'missed', [ 29, 30, 31 ], "2000-01-29" ], # successor delayed until 29th
   ) {
    my ($name, $schedule, $succ_creation_date) = @$test;

    subtest "heartbeat schedule: $name" => sub {
      $succ_creation_date ||= "2000-01-11"; # Should be created on Jan 11
      Moonpig->env->stop_clock_at($jan1);

      my $xid = "consumer:test:" . guid_string();
      do_with_fresh_ledger(
        {
          consumer => {
            template => 'boring2',
            xid  => $xid,
            cost_period => days(31),
            charge_amount => dollars(31),
          }
        },
        sub {
          my ($ledger) = @_;
          $ledger->register_event_handler(
            'contact-humans', 'default', Moonpig::Events::Handler::Noop->new()
          );

          my ($consumer) = $ledger->get_component("consumer");
          my @eq;
          $consumer->register_event_handler(
            'consumer-create-replacement', 'noname', queue_handler("ld", \@eq)
          );

          $self->heartbeat_and_send_mail($ledger);
          $self->assert_n_deliveries(1, "invoice");
          $self->pay_amount_due($ledger, dollars(31));

          for my $day (@$schedule) {
            my $tick_time = Moonpig::DateTime->new(
              year => 2000, month => 1, day => $day
             );
            Moonpig->env->stop_clock_at($tick_time);
            $self->heartbeat_and_send_mail(
              $ledger,
              { timestamp => $tick_time },
            );
          }
          is(@eq, 1, "received one request to create replacement (schedule '$name')");
          my ($receiver, $event) = @{$eq[0] || [undef, undef]};
          is($event->ident, 'consumer-create-replacement', "event name");
          is($event->payload->{timestamp}->ymd, $succ_creation_date, "event date");

          # This is sort of lame, but there it is.  It's once per three days
          # after the creation of the replacement. -- rjbs, 2012-09-07
          my $notices = $name eq 'missed' ? 1 : 6;
          $self->assert_n_deliveries($notices, "invoice for replacement");
        }
      );
    };
  }
};

test "irreplaceable" => sub {
  my ($self) = @_;
  plan tests => 3;

  for my $test (
    [ 'normal', [ 1 .. 31 ] ],  # one per day like it should be
    [ 'double', [ map( ($_,$_), 1 .. 31) ] ], # each one delivered twice
    [ 'missed', [ 29, 30, 31 ] ], # successor delayed until 29th
   ) {
    my ($name, $schedule) = @$test;
    subtest "heartbeat schedule: $name" => sub {
      my $xid = "consumer:test:" . guid_string();
      my $stuff;
      Moonpig->env->storage->do_rw(sub {
        $stuff = build(
          consumer => {
            class              => class('Consumer::ByTime::FixedAmountCharge'),
            charge_amount      => dollars(10),
            cost_period        => days(10),
            charge_description => "test charge",
            replacement_plan   => [ get => '/nothing' ],
            xid                => $xid,
            replacement_lead_time            => days(20),
          }
        );

        Moonpig->env->save_ledger($stuff->{ledger});

        my $ledger = $stuff->{ledger};

        $self->heartbeat_and_send_mail($ledger);
        $self->assert_n_deliveries(1, "invoice");
        $self->pay_amount_due($ledger, dollars(10));

        for my $day (@$schedule) {
          my $tick_time = Moonpig::DateTime->new(
            year => 2000, month => 1, day => $day
          );

          Moonpig->env->stop_clock_at($tick_time);
          $self->heartbeat_and_send_mail($stuff->{ledger});
        }
      });

      pass();
    };
  }
};

run_me;
done_testing;

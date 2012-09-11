use strict;
use warnings;

use Carp qw(confess croak);
use Data::GUID qw(guid_string);
use Moonpig;
use t::lib::TestEnv;
use t::lib::ConsumerTemplateSet::Test;
use List::AllUtils qw(uniq);
use Moonpig::Util -all;
use Test::More;
use Test::Routine::Util;
use Test::Routine;

use t::lib::Logger;
use Moonpig::Test::Factory qw(build do_with_fresh_ledger);

with(
  'Moonpig::Test::Role::LedgerTester',
);

test "charge" => sub {
  my ($self) = @_;

  my @tests = (
    [ 'normal', [ 1, 2, 3, 4 ], ],
    [ 'double', [ 1, 1, 2, 2, 3 ], ],
    [ 'missed', [ 2, 5 ], ],
  );

  plan tests => 0+@tests;

  # Pretend today is 2000-01-01 for convenience
  my $jan1 = Moonpig::DateTime->new( year => 2000, month => 1, day => 1 );

  for my $test (@tests) {
    Moonpig->env->stop_clock_at($jan1);
    my ($name, $schedule) = @$test;
    subtest "heartbeat schedule: $name" => sub {
      plan tests => 1 + @$schedule;
      my $stuff;
      Moonpig->env->storage->do_rw(sub {
        $stuff = build(
          consumer => {
            class              => class('Consumer::ByTime::FixedAmountCharge'),
            bank               => dollars(10),
            charge_amount      => dollars(1),
            cost_period        => days(1),
            replacement_plan   => [ get => '/nothing' ],
            charge_description => "test charge",
            xid                => xid(),
          }
        );

        Moonpig->env->save_ledger($stuff->{ledger});
      });

      $stuff->{consumer}->clear_grace_until;

      for my $day (@$schedule) {
        my $tick_time = Moonpig::DateTime->new(
          year => 2000, month => 1, day => $day
        );

        Moonpig->env->stop_clock_at($tick_time);

        $self->heartbeat_and_send_mail($stuff->{ledger});

        is(
          $stuff->{consumer}->unapplied_amount,
          dollars(10 - $day),
          sprintf('$%s remain', 10 - $day),
        );
      }

      $self->assert_n_deliveries(1, "invoice");
    };
  }
};

test "top up" => sub {
  my ($self) = @_;

  # Pretend today is 2000-01-01 for convenience
  my $jan = sub {
    Moonpig::DateTime->new( year => 2000, month => 1, day => $_[0] );
  };

  Moonpig->env->stop_clock_at($jan->(1));

  my $stuff;
  Moonpig->env->storage->do_rw(sub {
    $stuff = build(
      consumer => {
        class              => class('Consumer::ByTime::FixedAmountCharge'),
        bank               => dollars(10),
        charge_amount      => dollars(30),
        cost_period        => days(30),
        replacement_plan   => [ get => '/nothing' ],
        charge_description => "test charge",
        xid                => xid(),
      }
    );

    Moonpig->env->save_ledger($stuff->{ledger});
  });

  $stuff->{consumer}->abandon_all_unpaid_charges;
  $stuff->{consumer}->clear_grace_until;

  for my $day (2 .. 5) {
    my $tick_time = Moonpig::DateTime->new(
      year => 2000, month => 1, day => $day
    );

    Moonpig->env->stop_clock_at($tick_time);

    $self->heartbeat_and_send_mail($stuff->{ledger});

    is($stuff->{consumer}->unapplied_amount, dollars(10 - $day));

    cmp_ok(
      $stuff->{consumer}->expiration_date,
      '==',
      $jan->(11),
      "Jan $day, expiration predicted for Jan 11",
    );

    my $shortfall = $stuff->{consumer}->_predicted_shortfall;
    cmp_ok(
      abs($shortfall - days(20)), '<', $stuff->{consumer}->charge_frequency,
      "gonna expire 20 days early, +/- less than one charge cycle!"
    );
  }

  my $credit = $stuff->{ledger}->add_credit(
    class('Credit::Simulated'),
    { amount => dollars(20) },
  );

  $stuff->{ledger}->create_transfer({
    type   => 'consumer_funding',
    from   => $credit,
    to     => $stuff->{consumer},
    amount => dollars(20),
  });

  is(
    $stuff->{consumer}->_predicted_shortfall,
    0,
    "no longer predicting shortfall",
  );

  for my $day (5 .. 10) {
    my $tick_time = Moonpig::DateTime->new(
      year => 2000, month => 1, day => $day
    );

    Moonpig->env->stop_clock_at($tick_time);

    $self->heartbeat_and_send_mail($stuff->{ledger});

    is($stuff->{consumer}->unapplied_amount, dollars(30 - $day));

    cmp_ok(
      $stuff->{consumer}->expiration_date,
      '==',
      $jan->(31),
      "post top-up, Jan $day, expiration predicted for Jan 31",
    );
  }
};

test "proration" => sub {
  my ($self) = @_;

  # Pretend today is 2000-01-01 for convenience
  my $jan = sub {
    Moonpig::DateTime->new( year => 2000, month => 1, day => $_[0] );
  };

  Moonpig->env->stop_clock_at($jan->(1));

  my $stuff;
  Moonpig->env->storage->do_rw(sub {
    $stuff = build(
      consumer => {
        class              => class('Consumer::ByTime::FixedAmountCharge'),
        charge_amount      => dollars(30),
        cost_period        => days(100),
        proration_period   => days(10),
        replacement_plan   => [ get => '/nothing' ],
        charge_description => "test charge",
        xid                => xid(),
      }
    );

    Moonpig->env->save_ledger($stuff->{ledger});
  });

  $self->heartbeat_and_send_mail($stuff->{ledger});
  $self->assert_n_deliveries(1, "invoice");

  my @invoices = $stuff->{ledger}->payable_invoices;
  is(@invoices, 1, "we got a single invoice for our prorated consumer");

  is($invoices[0]->total_amount, dollars(3), 'it was for 10 days: $3');

  cmp_ok(
    $stuff->{consumer}->expiration_date,
    '==',
    $jan->(4),
    "expiration predicted for Jan 4",
  );
};

{
  package ChargeTodaysDate;
  use Moose::Role;
  use Moonpig::Util qw(dollars);
  use Moonpig::Types qw(PositiveMillicents);

  around initial_invoice_charge_structs => sub {
    my ($orig, $self) = @_;
    my @structs = $self->$orig;
    push @structs, {
      description => 'extra starting funds',
      amount      => dollars(100),
    };

    return @structs;
  };

  sub charge_structs_on {
    my ($self, $date) = @_;

    return ({
      description => 'service charge',
      amount      => dollars( $date->day ),
    });
  }
}

test "variable charge" => sub {
  my ($self) = @_;

  # Pretend today is 2000-01-01 for convenience
  my $jan1 = Moonpig::DateTime->new( year => 2000, month => 1, day => 1 );

  for my $test (
    # description, [ days to charge on ]
    [ 'normal', [ 1, 2, 3, 4, 5 ], ],
    [ 'double', [ 1, 1, 2, 2, 3, 3, 5, 5 ], ],
    [ 'missed', [ 2, 5 ], ],
  ) {
    Moonpig->env->stop_clock_at($jan1);
    my ($name, $schedule) = @$test;
    my $days = uniq @$schedule;

    subtest "heartbeat schedule: $name" => sub {
      my $stuff;
      Moonpig->env->storage->do_rw(sub {
        $stuff = build(
          consumer => {
            class => class('Consumer::ByTime', '=ChargeTodaysDate'),
            extra_charge_tags => ["test"],
            cost_period               => days(1),
            replacement_plan          => [ get => '/nothing' ],
            xid                       => xid(),
          }
        );

        my $credit = $stuff->{ledger}->add_credit(
          class('Credit::Simulated'),
          { amount => dollars(101) },
        );

        $stuff->{ledger}->perform_dunning;

        Moonpig->env->save_ledger($stuff->{ledger});
      });

      $stuff->{consumer}->clear_grace_until;

      for my $day (@$schedule) {
        my $tick_time = Moonpig::DateTime->new(
          year => 2000, month => 1, day => $day
        );

        Moonpig->env->stop_clock_at($tick_time);

        $self->heartbeat_and_send_mail($stuff->{ledger});
      }

      # We should be charging across five days, no matter the pattern, starting
      # on Jan 1, through Jan 5.  That's 1+2+3+4+5 = 15
      is($stuff->{consumer}->unapplied_amount, dollars(86),
         '$15 charged by charging the date');

      # Right now, we send psync notices.  We'd like to separate psync from
      # ByTime, but it's not trivial to do just this minute, so we'll make the
      # tests account for the psync notices. -- rjbs, 2012-09-07
      my $psyncs = $days - 1;
      $self->assert_n_deliveries(1 + $psyncs, "one invoice, $psyncs psyncs");
    };
  }
};

test cost_estimate => sub {
  my ($self) = @_;
  do_with_fresh_ledger(
    { c => { template => 'boring' } },
    sub {
      my ($ledger) = @_;
      my ($c) = $ledger->get_component("c");
      is($c->estimate_cost_for_interval({ interval => days(365) }), dollars(100), "cost estimate for 1y");
    });
};

test grace_period => sub {
  my ($self) = @_;

  for my $pair (
    # X,Y: expires after X days, set grace_until to Y
    [ 1, undef ],
    [ 2, Moonpig::DateTime->new( year => 2000, month => 1, day => 1 ) ],
    [ 3, Moonpig::DateTime->new( year => 2000, month => 1, day => 2 ) ],
  ) {
    my ($days, $until) = @$pair;

    subtest((defined $until ? "grace through $until" : "no grace") => sub {
      my $jan1 = Moonpig::DateTime->new( year => 2000, month => 1, day => 1 );
      Moonpig->env->stop_clock_at($jan1);

      my $stuff;
      Moonpig->env->storage->do_rw(sub {
        $stuff = build(
          consumer => {
            class              => class('Consumer::ByTime::FixedAmountCharge'),
            replacement_lead_time            => days(0),
            charge_amount        => dollars(1),
            cost_period        => days(1),
            replacement_plan   => [ get => '/nothing' ],
            charge_description => "test charge",
            xid                => xid(),
          }
        );

        Moonpig->env->save_ledger($stuff->{ledger});
      });
      my $c = $stuff->{consumer};

      if (defined $until) {
        $c->grace_until($until);
      } else {
        $c->clear_grace_until;
      }

      for my $day (1 .. $days) {
        my $tick_time = Moonpig::DateTime->new(
          year => 2000, month => 1, day => $day
        );

        Moonpig->env->stop_clock_at($tick_time);

        ok(
          ! $c->is_expired,
          sprintf("as of %s, consumer is not expired", q{} . Moonpig->env->now),
        );

        $self->heartbeat_and_send_mail($stuff->{ledger});
      }

      $self->assert_n_deliveries(
        $until ? (1, "the invoice") : (0, "expired before invoicing")
      );

      ok(
        $c->is_expired,
        sprintf("as of %s, consumer is expired", q{} . Moonpig->env->now),
      );
    });
  }
};

test "spare change" => sub {
  my ($self) = @_;

  # Pretend today is 2000-01-01 for convenience
  my $jan1 = Moonpig::DateTime->new( year => 2000, month => 1, day => 1 );
  Moonpig->env->stop_clock_at($jan1);

  Moonpig->env->storage->do_rw(sub {
    my $stuff = build(
      consumer => {
        class              => class('Consumer::ByTime::FixedAmountCharge'),
        bank               => dollars(100),
        charge_amount      => dollars(100),
        cost_period        => days(100),
        replacement_plan   => [ get => '/nothing' ],
        charge_description => "test charge",
        xid                => xid(),
      }
    );

    my $ledger   = $stuff->{ledger};
    my $consumer = $stuff->{consumer};

    Moonpig->env->elapse_time(86_400 * 10);
    $ledger->heartbeat;
    $self->assert_n_deliveries(1, "invoice");

    is($ledger->amount_available, 0, "we have no free cash on the ledger");
    my $funds = $consumer->unapplied_amount;
    cmp_ok($funds, '>', 0, "the consumer has some cash");

    $stuff->{consumer}->expire;
    $ledger->heartbeat;

    is($consumer->unapplied_amount, 0, "...the funds are gone from consumer");
    is($ledger->amount_available, $funds, "...the funds went to the ledger!");
  });
};

test "almost no spare change" => sub {
  my ($self) = @_;

  # Pretend today is 2000-01-01 for convenience
  my $jan1 = Moonpig::DateTime->new( year => 2000, month => 1, day => 1 );
  Moonpig->env->stop_clock_at($jan1);

  Moonpig->env->storage->do_rw(sub {
    my $stuff = build(
      consumer => {
        class              => class('Consumer::ByTime::FixedAmountCharge'),
        bank               => dollars(1),   # less than one day's charge
        charge_amount      => dollars(200),
        cost_period        => days(100),
        replacement_plan   => [ get => '/nothing' ],
        charge_description => "test charge",
        xid                => xid(),
      }
    );

    my $ledger   = $stuff->{ledger};
    my $consumer = $stuff->{consumer};

    Moonpig->env->elapse_time(86_400);
    $ledger->heartbeat;
    $self->assert_n_deliveries(1, "invoice");

    is($ledger->amount_available, 0, "we have no free cash on the ledger");
    my $funds = $consumer->unapplied_amount;
    cmp_ok($funds, '>', 0, "the consumer has some cash");

    $stuff->{consumer}->expire;
    $ledger->_collect_spare_change;

    is($consumer->unapplied_amount, 0, "...the funds are gone from consumer");
    is($ledger->amount_available, 0, "...and the ledger didn't get them!");
  });
};

test "abandon unfunded charges" => sub {
  my ($self) = @_;

  my $jan1 = Moonpig::DateTime->new( year => 2000, month => 1, day => 1 );
  Moonpig->env->stop_clock_at($jan1);

  do_with_fresh_ledger(
    { c => { template => 'boring' } },
    sub {
      my ($ledger) = @_;
      my ($c) = $ledger->get_component("c");

      $ledger->heartbeat;
      $self->assert_n_deliveries(1, "invoice");
      is($ledger->amount_due, dollars(100), '$100 due to start');

      Moonpig->env->elapse_time(86_400 * 40);
      $ledger->heartbeat;
      is($ledger->amount_due, 0, '...but we abandon it when never paid');
    }
  );
};

sub xid { "test:consumer:" . guid_string() }

run_me;
done_testing;

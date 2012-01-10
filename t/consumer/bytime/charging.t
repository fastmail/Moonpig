use strict;
use warnings;

use Carp qw(confess croak);
use Data::GUID qw(guid_string);
use Moonpig;
use t::lib::TestEnv;
use Moonpig::Util -all;
use Test::More;
use Test::Routine::Util;
use Test::Routine;

use t::lib::Logger;
use Moonpig::Test::Factory qw(build);

with(
  'Moonpig::Test::Role::UsesStorage',
);

test "charge" => sub {
  my ($self) = @_;

  plan tests => (4 + 5 + 2);

  # Pretend today is 2000-01-01 for convenience
  my $jan1 = Moonpig::DateTime->new( year => 2000, month => 1, day => 1 );

  for my $test (
    [ 'normal', [ 1, 2, 3, 4 ], ],
    [ 'double', [ 1, 1, 2, 2, 3 ], ],
    [ 'missed', [ 2, 5 ], ],
  ) {
    Moonpig->env->stop_clock_at($jan1);
    my ($name, $schedule) = @$test;
    note("testing with heartbeat schedule '$name'");

    my $stuff;
    Moonpig->env->storage->do_rw(sub {
      $stuff = build(
        consumer => {
          class              => class('Consumer::ByTime::FixedAmountCharge'),
          bank               => dollars(10),
          replacement_lead_time            => years(1000),
          charge_amount        => dollars(1),
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

      is($stuff->{consumer}->unapplied_amount, dollars(10 - $day));
    }
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
        replacement_lead_time => years(1000),
      }
    );

    Moonpig->env->save_ledger($stuff->{ledger});
  });

  $stuff->{consumer}->clear_grace_until;

  for my $day (2 .. 5) {
    my $tick_time = Moonpig::DateTime->new(
      year => 2000, month => 1, day => $day
    );

    Moonpig->env->stop_clock_at($tick_time);

    $self->heartbeat_and_send_mail($stuff->{ledger});

    is($stuff->{consumer}->unapplied_amount, dollars(10 - $day));

    cmp_ok(
      $stuff->{consumer}->expire_date,
      '==',
      $jan->(11),
      "Jan $day, expiration predicted for Jan 11",
    );
  }

  my $credit = $stuff->{ledger}->add_credit(
    class('Credit::Simulated'),
    { amount => dollars(20) },
  );

  $stuff->{ledger}->create_transfer({
    type   => 'test_consumer_funding',
    from   => $credit,
    to     => $stuff->{consumer},
    amount => dollars(20),
  });

  for my $day (5 .. 10) {
    my $tick_time = Moonpig::DateTime->new(
      year => 2000, month => 1, day => $day
    );

    Moonpig->env->stop_clock_at($tick_time);

    $self->heartbeat_and_send_mail($stuff->{ledger});

    is($stuff->{consumer}->unapplied_amount, dollars(30 - $day));

    cmp_ok(
      $stuff->{consumer}->expire_date,
      '==',
      $jan->(31),
      "post top-up, Jan $day, expiration predicted for Jan 31",
    );
  }
};

{
  package ChargeTodaysDate;
  use Moose::Role;
  use Moonpig::Util qw(dollars);
  use Moonpig::Types qw(PositiveMillicents);

  sub charge_pairs_on {
    my ($self, $date) = @_;

    return ('service charge' => dollars( $date->day ));
  }
}

test "variable charge" => sub {
  my ($self) = @_;

  my @eq;

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
    note("testing with heartbeat schedule '$name'");

    my $stuff;
    Moonpig->env->storage->do_rw(sub {
      $stuff = build(
        consumer => {
          class => class('Consumer::ByTime', '=ChargeTodaysDate'),
          bank  => dollars(500),
          extra_journal_charge_tags => ["test"],
          replacement_lead_time                   => years(1000),
          cost_period               => days(1),
          replacement_plan          => [ get => '/nothing' ],
          xid                       => xid(),
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

    }

    # We should be charging across five days, no matter the pattern, starting
    # on Jan 1, through Jan 5.  That's 1+2+3+4+5 = 15
    is($stuff->{consumer}->unapplied_amount, dollars(485),
       '$15 charged by charging the date');
  }
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
        ok(
          ! $c->is_expired,
          sprintf("as of %s, consumer is not expired", q{} . Moonpig->env->now),
        );

        my $tick_time = Moonpig::DateTime->new(
          year => 2000, month => 1, day => $day
        );

        Moonpig->env->stop_clock_at($tick_time);

        $self->heartbeat_and_send_mail($stuff->{ledger});
      }

      ok(
        $c->is_expired,
        sprintf("as of %s, consumer is expired", q{} . Moonpig->env->now),
      );
    });
  }
};

sub xid { "test:consumer:" . guid_string() }

run_me;
done_testing;

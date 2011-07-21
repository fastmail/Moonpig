use strict;
use warnings;

use Carp qw(confess croak);
use Moonpig;
use Moonpig::Env::Test;
use Moonpig::Util -all;
use Test::More;
use Test::Routine::Util;
use Test::Routine;

use t::lib::Logger;

my $CLASS = class('Consumer::ByTime::FixedCost');

sub fresh_ledger {
  my ($self) = @_;

  my $ledger;

  Moonpig->env->storage->do_rw(sub {
    $ledger = $self->test_ledger;
    Moonpig->env->save_ledger($ledger);
  });

  return $ledger;
}

has ledger => (
  is => 'rw',
  does => 'Moonpig::Role::Ledger',
  lazy => 1,
  default => sub { $_[0]->fresh_ledger },
  clearer => 'clear_ledger',
);
sub ledger;  # Work around bug in Moose 'requires';

with(
  't::lib::Factory::Consumers',
  't::lib::Factory::Ledger',
  't::lib::Role::UsesStorage',
 );

after run_test => sub { $_[0]->clear_ledger };

test "charge" => sub {
  my ($self) = @_;

  my @eq;

  plan tests => 4 + 5 + 2;

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

    my $b = class('Bank')->new({
      ledger => $self->ledger,
      amount => dollars(10),	# One dollar per day for rest of January
    });

    my $c = $self->test_consumer(
      $CLASS, {
        ledger => $self->ledger,
        bank => $b,
        old_age => years(1000),
        cost_amount        => dollars(1),
        cost_period        => days(1),
        replacement_mri    => Moonpig::URI->nothing(),
    });

    $c->clear_grace_until;

    for my $day (@$schedule) {
      my $tick_time = Moonpig::DateTime->new(
        year => 2000, month => 1, day => $day
      );

      Moonpig->env->stop_clock_at($tick_time);

      $self->heartbeat_and_send_mail($self->ledger);

      is($b->unapplied_amount, dollars(10 - $day));
    }
  }
};

{
  package CostsTodaysDate;
  use Moose::Role;
  use Moonpig::Util qw(dollars);
  use Moonpig::Types qw(PositiveMillicents);

  sub costs_on {
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

    my $b = class('Bank')->new({
      ledger => $self->ledger,
      amount => dollars(500),
    });

    my $c = $self->test_consumer(
      class('Consumer::ByTime', '=CostsTodaysDate'),
      {
        # These would come from defaults if this wasn't a weird-o class. --
        # rjbs, 2011-05-17
        extra_charge_tags => [ "test" ],
        ledger          => $self->ledger,
        bank            => $b,
        old_age         => years(1000),
        cost_period     => days(1),
        replacement_mri => Moonpig::URI->nothing(),
    });

    $c->clear_grace_until;

    for my $day (@$schedule) {
      my $tick_time = Moonpig::DateTime->new(
        year => 2000, month => 1, day => $day
      );

      Moonpig->env->stop_clock_at($tick_time);

      $self->heartbeat_and_send_mail($self->ledger);

    }

    # We should be charging across five days, no matter the pattern, starting
    # on Jan 1, through Jan 5.  That's 1+2+3+4+5 = 15
    is($b->unapplied_amount, dollars(485), '$15 charged by charging the date');
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

      $self->ledger( $self->fresh_ledger );

      my $c = $self->test_consumer(
        $CLASS,
        { cost_amount        => dollars(1),
          cost_period        => days(1),
          old_age            => days(0),
          replacement_mri    => Moonpig::URI->nothing(),
        }
      );

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

        $self->heartbeat_and_send_mail($self->ledger);
      }

      ok(
        $c->is_expired,
        sprintf("as of %s, consumer is expired", q{} . Moonpig->env->now),
      );
    });
  }
};

run_me;
done_testing;

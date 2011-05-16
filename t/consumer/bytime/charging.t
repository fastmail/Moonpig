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

has ledger => (
  is => 'rw',
  does => 'Moonpig::Role::Ledger',
  default => sub { $_[0]->test_ledger() },
);
sub ledger;  # Work around bug in Moose 'requires';

with(
  't::lib::Factory::Consumers',
  't::lib::Factory::Ledger',
  't::lib::Role::UsesStorage',
 );

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

      $self->ledger( $self->test_ledger );

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

use strict;
use warnings;

use Carp qw(confess croak);
use Moonpig;
use Moonpig::Consumer::ByTime;
use Moonpig::Env::Test;
use Moonpig::Util -all;
use Test::More;
use Test::Routine::Util;
use Test::Routine;

my $CLASS = "Moonpig::Consumer::ByTime";

has ledger => (
  is => 'rw',
  does => 'Moonpig::Role::Ledger',
  default => sub { $_[0]->test_ledger() },
);
sub ledger;  # Work around bug in Moose 'requires';

with ('t::lib::Factory::Consumers',
      't::lib::Factory::Ledger',
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
    Moonpig->env->current_time($jan1);
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
      });

    for my $day (@$schedule) {
      my $tick_time = Moonpig::DateTime->new(
        year => 2000, month => 1, day => $day
      );

      $c->handle_event(event('heartbeat', { timestamp => $tick_time }));
      is($b->unapplied_amount, dollars(10 - $day));
    }
  }
};

run_me;
done_testing;

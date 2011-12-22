use Test::Routine;
use Test::Routine::Util -all;
use Test::More;
use Test::Fatal;

use t::lib::TestEnv;
use Moonpig::DateTime;

before "run_test" => sub {
  Moonpig->env->reset_clock;
};

sub within_a_second {
  my ($time_1, $time_2, $comment) = @_;

  local $Test::Builder::Level = $Test::Builder::Level + 1;

  map { $_ = $_->epoch if ref } ($time_1, $time_2);

  cmp_ok( abs($time_1 - $time_2), '<=', 1, $comment );
}

sub is_nowish {
  my ($time, $comment) = @_;

  local $Test::Builder::Level = $Test::Builder::Level + 1;

  within_a_second(time, $time, $comment);
}

test "wallclock" => sub {
  my ($self) = @_;

  is_nowish( Moonpig->env->now, "env->now");
  sleep 1;
  is_nowish( Moonpig->env->now, "env->now");

  Moonpig->env->restart_clock; # noop

  like(
    (exception { Moonpig->env->elapse_time(30) })->ident,
    qr/not stopped/,
    "can't elapse time against the wall clock",
  );
};

test "stopped clock" => sub {
  my ($self) = @_;

  my $t = Moonpig->env->now();

  is_nowish($t, 'env->now');

  my $epoch = Moonpig::DateTime->new(
    year      => 1978,
    month     => 7,
    day       => 20,
    hour      => 5,
    minute    => 0,
    second    => 0,
    time_zone => "UTC",
  );

  Moonpig->env->stop_clock_at($epoch);
  cmp_ok(Moonpig->env->now, '==', $epoch, "the clock is stopped at $epoch");

  Moonpig->env->stop_clock_at($epoch + 30);
  cmp_ok(abs($epoch - Moonpig->env->now), '==', 30, "env->now is +30");

  Moonpig->env->elapse_time(30);
  cmp_ok(abs($epoch - Moonpig->env->now), '==', 60, "env->now is +60");

  like(
    (exception { Moonpig->env->elapse_time(-30) })->ident,
    qr/negative time/,
    "can't elapse negative time",
  );
};

test "offset clock" => sub {
  my ($self) = @_;

  my $epoch = Moonpig::DateTime->new(
    year      => 1978,
    month     => 7,
    day       => 20,
    hour      => 5,
    minute    => 0,
    second    => 0,
    time_zone => "UTC",
  );

  Moonpig->env->stop_clock_at($epoch);
  cmp_ok(Moonpig->env->now, '==', $epoch, "the clock is stopped at $epoch");

  Moonpig->env->restart_clock;

  sleep 1;
  within_a_second( Moonpig->env->now, $epoch + 1, "a second passed");

  sleep 1;
  within_a_second( Moonpig->env->now, $epoch + 2, "another second passed");

  like(
    (exception { Moonpig->env->elapse_time(30) })->ident,
    qr/not stopped/,
    "can't elapse time against the wall clock",
  );

  Moonpig->env->stop_clock;

  sleep 2;
  within_a_second( Moonpig->env->now, $epoch + 2, "clock is stopped again");
};

run_me;
done_testing;

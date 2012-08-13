use Test::Routine;

use t::lib::TestEnv;
use t::lib::Logger '$Logger';

use Carp qw(confess croak);
use DateTime;
use Moonpig::Util -all;
use Test::Deep qw(cmp_deeply);
use Test::Fatal;
use Test::More;
use Test::Routine::Util;
use Try::Tiny;

with ('Moonpig::Test::Role::UsesStorage');
use Moonpig::Test::Factory qw(do_with_fresh_ledger);

test "fixed-expiration consumer" => sub {
  my ($self) = @_;

  do_with_fresh_ledger({}, sub {
    my ($ledger) = @_;
    Moonpig->env->stop_clock;
    my $expiration_date = Moonpig->env->now + days(30);

    my $c = $ledger->add_consumer(
      class('Consumer::FixedExpiration::Required'),
      {
        xid => "some:random:xid",
        make_active => 1,
        expiration_date  => $expiration_date,
        replacement_plan => [ get => '/nothing' ],
      },
    );

    isa_ok($c, class('Consumer::FixedExpiration::Required'));
    is($c->remaining_life, days(30), "initial remaining life");

    $ledger->heartbeat;
    is($c->remaining_life, days(30), "remaining life after first heartbeat");
    is($c->expiration_date, $expiration_date, "expire date is as created");

    Moonpig->env->elapse_time( days(20) );
    $ledger->heartbeat;
    is($c->remaining_life, days(10), "remaining life after 20 days");
    ok( ! $c->is_expired, "consumer has not expired after 20 days");

    Moonpig->env->elapse_time( days(20) );
    $ledger->heartbeat;
    is($c->remaining_life, days(0), "remaining life after 40 days is zero");
    ok(   $c->is_expired, "consumer has expired after 40 days");
  });
};

run_me;
done_testing;

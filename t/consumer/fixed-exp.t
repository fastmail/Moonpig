use Test::Routine;

use Moonpig::Env::Test;
use t::lib::Logger '$Logger';

use Moonpig::Context::Test '-all', '$Context';

use Carp qw(confess croak);
use DateTime;
use Moonpig::Events::Handler::Code;
use Moonpig::Util -all;
use Test::Deep qw(cmp_deeply);
use Test::Fatal;
use Test::More;
use Test::Routine::Util;
use Try::Tiny;

with ('t::lib::Role::UsesStorage');
use t::lib::Factory qw(build);

test "fixed-expiration consumer" => sub {
  my ($self) = @_;

  Moonpig->env->storage->do_rw(sub {
    Moonpig->env->stop_clock;
    my $expire_date = Moonpig->env->now + days(30);

    my $stuff = build(c => {
      class => class('Consumer::FixedExpiration'),
      expire_date => $expire_date,
      replacement_plan => [ get => '/nothing' ],
    });
    my $c = $stuff->{c};
    my $ledger = $c->ledger;

    isa_ok($c, class('Consumer::FixedExpiration'));

    $ledger->handle_event( event('heartbeat') );

    is($c->expire_date, $expire_date, "expire date is as created");

    Moonpig->env->elapse_time( days(20) );

    $ledger->handle_event( event('heartbeat') );

    ok( ! $c->is_expired, "consumer has not expired after 20 days");

    Moonpig->env->elapse_time( days(20) );

    $ledger->handle_event( event('heartbeat') );

    ok(   $c->is_expired, "consumer has expired after 40 days");
  });
};

run_me;
done_testing;

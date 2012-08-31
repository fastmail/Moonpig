#!/usr/bin/env perl
use Test::Routine;
use Test::Routine::Util -all;
use Test::More;

use t::lib::TestEnv;
use t::lib::ConsumerTemplateSet::Test;

with(
  'Moonpig::Test::Role::LedgerTester',
);

use t::lib::Logger '$Logger';
use Moonpig::Test::Factory qw(do_with_fresh_ledger);

use Moonpig::Util qw(class days dollars event);

test "cost_estimate" => sub {
  my ($self) = @_;

  do_with_fresh_ledger(
    { a => { template => 'boring'},
      b => { template => 'boring', charge_amount => dollars(10) },
      c => { template => 'boring', cost_period => days(730) },
    },
    sub {
      my ($ledger) = @_;
      is($ledger->estimate_cost_for_interval({ interval => days(365) }),
         dollars(100 + 10 + 100/2),
         "estimate for three various consumers");
    },
  );
};

run_me;
done_testing;

#!/usr/bin/env perl
use Test::Routine;
use Test::Routine::Util '-all';
use Test::More;

use t::lib::TestEnv;

use Moonpig::Test::Factory qw(do_with_fresh_ledger);

with(
  'Moonpig::Test::Role::LedgerTester',
);

use t::lib::TestEnv;

use Moonpig::Util qw(class days dollars);

use t::lib::ConsumerTemplateSet::Demo;

use namespace::autoclean;

test "check amounts" => sub {
  my ($self) = @_;

  Moonpig->env->stop_clock;

  do_with_fresh_ledger({
      consumer => {
          template    => 'demo-service',
          xid         => "test:thing:xid",
          make_active => 1,
      }}, sub {
    my ($ledger) = @_;

    Moonpig->env->elapse_time(days(1));
    $ledger->heartbeat;
    $self->assert_n_deliveries(1, "invoice");

    my ($inv) = $ledger->payable_invoices;

    my $amount = $inv->total_amount;
    is($amount, dollars(50), "charge for the right amount");

    $ledger->add_credit(
      class(qw(Credit::Simulated)),
      { amount => $amount },
    );

    $ledger->process_credits;

    ok($inv->is_paid, "invoice paid");
    is(
      $ledger->get_component('consumer')->unapplied_amount,
      $amount,
      "consumer funded for correct amount",
    );
  });
};

run_me;
done_testing;

#!/usr/bin/env perl
use Test::Routine;
use Test::Routine::Util '-all';
use Test::More;

use t::lib::TestEnv;

use Moonpig::Test::Factory qw(do_with_fresh_ledger);

with(
  'Moonpig::Test::Role::UsesStorage',
);

use t::lib::TestEnv;

use Moonpig::Util qw(class days event);

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

    my $inv;
    do {
        $ledger->handle_event( event('heartbeat') );
        Moonpig->env->elapse_time(days(1));
    } until $inv = $self->payable_invoice($ledger);

    my $amount = $inv->total_amount;
    note "Found invoice for amount $amount; paying\n";

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

sub payable_invoice {
  my ($self, $ledger) = @_;
  my ($inv) = grep { ! $_->is_open and ! $_->is_paid }
    $ledger->invoices;
  return $inv;
}

run_me;
done_testing;

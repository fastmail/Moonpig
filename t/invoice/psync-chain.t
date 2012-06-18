use Test::Routine;
use Test::More;
use Test::Routine::Util;
use Test::Fatal;

use t::lib::TestEnv;
use Stick::Util qw(ppack);

use Moonpig::Util qw(class days dollars event weeks years);

with(
  't::lib::Factory::EventHandler',
  'Moonpig::Test::Role::LedgerTester',
);

use t::lib::ConsumerTemplateSet::Test;
use Moonpig::Test::Factory qw(do_with_fresh_ledger);

my $jan1 = Moonpig::DateTime->new( year => 2000, month => 1, day => 1 );

before run_test => sub {
  Moonpig->env->email_sender->clear_deliveries;
  Moonpig->env->stop_clock_at($jan1);
};

sub do_test (&) {
  my ($code) = @_;
  do_with_fresh_ledger({ c => { template => 'psync' } }, sub {
    my ($ledger) = @_;
    my $c = $ledger->get_component("c");
    $c->_adjust_replacement_chain(days(14));
    my ($credit) = $ledger->add_credit(
      class(qw(Credit::Simulated)),
      { amount => dollars(21) },
    );
    $ledger->name_component("credit", $credit);
    my $d = $c->replacement;
    $ledger->name_component("d", $d);
    my $e = $d->replacement;
    $ledger->name_component("e", $e);

    $code->($ledger, $c, $d, $e);
  });
}

sub get_single_delivery {
  my ($msg) = @_;
  $msg //= "exactly one delivery";
  Moonpig->env->process_email_queue;
  my $sender = Moonpig->env->email_sender;
  is(my ($delivery) = $sender->deliveries, 1, $msg);
  $sender->clear_deliveries;
  return $delivery;
}

sub elapse {
  my ($ledger, $days) = @_;
  $days //= 1;
  Moonpig->env->elapse_time(86_400 * $days);
  $ledger->heartbeat;
}

test 'setup sanity checks' => sub {
  do_test {
    my ($ledger, $c, $d, $e) = @_;
    ok($c);
    ok($c->does('Moonpig::Role::Consumer::ByTime'));
    ok($c->does("t::lib::Role::Consumer::VaryingCharge"));
    is($c->_predicted_shortfall, 0, "initially no predicted shortfall");
    is($c->expected_funds({ include_unpaid_charges => 1 }), dollars(7),
       "expected funds incl unpaid");
    is($c->expected_funds({ include_unpaid_charges => 0 }), 0, "expected funds not incl unpaid");
    is($c->_estimated_remaining_funded_lifetime({ amount => dollars(7) }), days(7),
      "est lifetime 7d");

    { my @chain = $c->replacement_chain;
      is(@chain, 2, "replacement chain length");
      ok(! $chain[0]->is_active, "chain 0 not yet active");
      ok(! $chain[1]->is_active, "chain 1 not yet active");
      ok(  $c->is_active, "initial consumer is active");
      is($d->guid, $chain[0]->guid, "\$d set up");
      is($e->guid, $chain[1]->guid, "\$e set up");
    }

    note "Elapsing a day on the ledger to clear payment";
    elapse($ledger);

    is($c->expected_funds({ include_unpaid_charges => 1 }), dollars(7),
       "expected funds incl unpaid");
    is($c->expected_funds({ include_unpaid_charges => 0 }), dollars(7),
       "expected funds not incl unpaid");
    is($c->unapplied_amount, dollars(7), "did not spend any money yet");
    is($c->_predicted_shortfall, 0, "initially no predicted shortfall");

    my @inv = $ledger->invoices;
    is(@inv, 1, "one invoice");
    ok($inv[0]->is_closed, "the invoice is closed");
    ok($inv[0]->is_paid, "the invoice is paid");

    my @qu = $ledger->quotes;
    is(@qu, 0, "no quotes");

  };
};

test 'psync chains' => sub {
  do_test {
    my ($ledger, $c, $d, $e) = @_;
    subtest "psync quote" => sub {
      $_->total_charge_amount(dollars(10)) for $c, $d, $e;
      is($_->_predicted_shortfall, days(3), "extra charge -> shortfall 3 days")
        for $c, $d, $e;
      elapse($ledger);

      is(my ($qu) = $ledger->quotes, 1, "psync quote generated");
      ok($qu->is_closed, "quote is closed");
      ok($qu->is_psync_quote, "quote is a psync quote");
      is($qu->psync_for_xid, $c->xid, "quote's psync xid is correct");

      is (my (@ch) = $qu->all_charges, 3, "three charges on psync quote");
      subtest "psync charge amounts" => sub {
        is($_->amount, dollars(3)) for @ch;
      };
      is ($qu->total_amount, dollars(9), "psync total amount");

      Moonpig->env->process_email_queue;
      my $sender = Moonpig->env->email_sender;
      my ($delivery) = get_single_delivery("one email delivery (the psync quote)");
    };
  };

};

run_me;
done_testing;

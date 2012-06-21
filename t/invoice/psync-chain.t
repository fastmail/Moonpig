use strict;
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
    $c->_adjust_replacement_chain(days(28));
    my ($credit) = $ledger->add_credit(
      class(qw(Credit::Simulated)),
      { amount => dollars(42) },
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
  for (1 .. $days) {
    $ledger->heartbeat;
    Moonpig->env->elapse_time(86_400);
  }
}

test 'setup sanity checks' => sub {
  do_test {
    my ($ledger, $c, $d, $e) = @_;
    ok($c);
    ok($c->does('Moonpig::Role::Consumer::ByTime'));
    ok($c->does("t::lib::Role::Consumer::VaryingCharge"));
    is($c->_predicted_shortfall, 0, "initially no predicted shortfall");
    is($c->expected_funds({ include_unpaid_charges => 1 }), dollars(14),
       "expected funds incl unpaid");
    is($c->expected_funds({ include_unpaid_charges => 0 }), 0, "expected funds not incl unpaid");
    is($c->_estimated_remaining_funded_lifetime({ amount => dollars(14) }), days(14),
      "est lifetime 7d");

    { my @chain = $c->replacement_chain;
      is(@chain, 2, "replacement chain length");
      ok(! $chain[0]->is_active, "chain 0 not yet active");
      ok(! $chain[1]->is_active, "chain 1 not yet active");
      ok(  $c->is_active, "initial consumer is active");
      is($d->guid, $chain[0]->guid, "\$d set up");
      is($e->guid, $chain[1]->guid, "\$e set up");
    }

    $ledger->perform_dunning; # close the invoice and process the credit

    is($c->expected_funds({ include_unpaid_charges => 1 }), dollars(14),
       "expected funds incl unpaid");
    is($c->expected_funds({ include_unpaid_charges => 0 }), dollars(14),
       "expected funds not incl unpaid");
    is($c->unapplied_amount, dollars(14), "did not spend any money yet");
    is($c->_predicted_shortfall, 0, "initially no predicted shortfall");

    my @inv = $ledger->invoices;
    is(@inv, 1, "one invoice");
    ok($inv[0]->is_closed, "the invoice is closed");
    ok($inv[0]->is_paid, "the invoice is paid");

    { Moonpig->env->process_email_queue;
      my ($delivery) = get_single_delivery("discarding initial invoice");
      Moonpig->env->email_sender->clear_deliveries;
      (() = Moonpig->env->email_sender->deliveries) == 0 or die;
    }

    my @qu = $ledger->quotes;
    is(@qu, 0, "no quotes");

  };
};

test 'psync chains' => sub {
  do_test {
    my ($ledger, $c, $d, $e) = @_;

    # At this point, 14 days and $14 remain

    subtest "psync quote" => sub {
      $_->total_charge_amount(dollars(20)) for $c, $d, $e;
      # At $20/14 per day, the $14 remaining will be used up in 196/20 days,
      # leaving a shortfall of 14 - 196/20 = 42/10 days.
      is($_->_predicted_shortfall, days(4.2), "extra charge -> shortfall 4.2 days")
        for $c, $d, $e;
      elapse($ledger);

      is(my ($qu) = $ledger->quotes, 1, "psync quote generated");
      ok($qu->is_closed, "quote is closed");
      ok($qu->is_psync_quote, "quote is a psync quote");
      is($qu->psync_for_xid, $c->xid, "quote's psync xid is correct");

      is (my (@ch) = $qu->all_charges, 3, "three charges on psync quote");
      subtest "psync charge amounts" => sub {
        is($_->amount, dollars(6)) for @ch;
      };
      is ($qu->total_amount, dollars(18), "psync total amount");
    };

    subtest "psync email" => sub {
      Moonpig->env->process_email_queue;
      # throw away the invoice.
      my @deliveries = grep {$_->{email}->header('Subject') ne "PAYMENT IS DUE"}
        Moonpig->env->email_sender->deliveries;
      is(@deliveries, 1, "psync quote was emailed");
      Moonpig->env->email_sender->clear_deliveries;
    };
  };

};

run_me;
done_testing;

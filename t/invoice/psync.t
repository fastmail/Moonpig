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

use t::lib::ConsumerTemplateSet::Demo;
use t::lib::ConsumerTemplateSet::Test;
use Moonpig::Test::Factory qw(do_with_fresh_ledger);

my $jan1 = Moonpig::DateTime->new( year => 2000, month => 1, day => 1 );

before run_test => sub {
  Moonpig->env->email_sender->clear_deliveries;
  Moonpig->env->stop_clock_at($jan1);
};

sub do_test (&) {
  my ($code) = @_;
  do_with_fresh_ledger({ c => { template => 'psync',
                                replacement_plan => [ get => '/nothing' ],
                              }}, sub {
    my ($ledger) = @_;
    my $c = $ledger->get_component("c");
    my ($credit) = $ledger->credit_collection->add({
      type => 'Simulated',
      attributes => { amount => dollars(14) }
    });
    $ledger->name_component("credit", $credit);

    $code->($ledger, $c);
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
    my ($ledger, $c) = @_;
    ok($c);
    ok($c->does('Moonpig::Role::Consumer::ByTime'));
    ok($c->does("t::lib::Role::Consumer::VaryingCharge"));
    is($c->_predicted_shortfall, 0, "initially no predicted shortfall");
    is($c->expected_funds({ include_unpaid_charges => 1 }), dollars(14),
       "expected funds incl unpaid");
    is($c->expected_funds({ include_unpaid_charges => 0 }), 0, "expected funds not incl unpaid");
    is($c->_estimated_remaining_funded_lifetime({ amount => dollars(14) }), days(14),
      "est lifetime 14d");

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

    my @qu = $ledger->quotes;
    is(@qu, 0, "no quotes");

  };
};

test 'quote' => sub {
  do_test {
    my ($ledger, $c) = @_;
    my $sender = Moonpig->env->email_sender;

    subtest "do not send psync quotes until rate changes" => sub {
      is($c->_predicted_shortfall, 0, "initially no predicted shortfall");
      elapse($ledger);
      is(scalar($ledger->quotes), 0, "no quotes yet");
      elapse($ledger);
      is(scalar($ledger->quotes), 0, "no quotes yet");

      Moonpig->env->process_email_queue;
      get_single_delivery("one email delivery (the invoice)");
    };
    # At this point, 12 days and $12 remain

    subtest "generate psync quote when rate changes" => sub {
      elapse($ledger);
      # Have $14-$3 = $11; now spending $2/day => lifetime = 5.5d
      # remaining lifetime should have been 14-3 = 11d.
      # To top up the account, need to get $1 per remaining day = $11
      $c->total_charge_amount(dollars(28));
      is($c->_predicted_shortfall, days(5.5), "double charge -> shortfall 5.5d");
      elapse($ledger) until $ledger->quotes;

      is(my ($qu) = $ledger->quotes, 1, "psync quote generated");
      ok($qu->is_closed, "quote is closed");
      ok($qu->is_psync_quote, "quote is a psync quote");
      is($qu->psync_for_xid, $c->xid, "quote's psync xid is correct");
      { my @old = $ledger->find_old_psync_quotes($c->xid);
        ok(@old == 1 && $old[0] == $qu, "find_old_psync_quotes");
      }

      is (my ($ch) = $qu->all_charges, 1, "one charge on psync quote");
      ok($ch->has_tag("moonpig.psync"), "charge is properly tagged");
      ok($ch->has_tag($c->xid), "charge has correct xid tag");
      is($ch->owner_guid, $c->guid, "charge owner");
      is($ch->amount, dollars(11), "charge amount");

      Moonpig->env->process_email_queue;
      my $sender = Moonpig->env->email_sender;
      my ($delivery) = get_single_delivery("one email delivery (the psync quote)");
    };

    subtest "do not generate further quotes or send further email" => sub {
      elapse($ledger, 1) until $c->is_expired;
      is(my ($qu) = $ledger->quotes, 1, "no additional psync quotes generated");
      Moonpig->env->process_email_queue;
      my $sender = Moonpig->env->email_sender;
      is(my ($delivery) = $sender->deliveries, 0, "no additional email delivered");
    };
  };
};

test 'varying charges' => sub {
  do_test {
    my ($ledger, $c) = @_;
    my $sender = Moonpig->env->email_sender;
    my ($q1, $q2, $q3);

    subtest "rate goes up to 28" => sub {
      elapse($ledger, 3);
      $c->total_charge_amount(dollars(28));
      elapse($ledger);
      # At this point, 10 days and $9 remain
      is(($q1) = $ledger->quotes, 1, "first psync quote generated");
      is($q1->total_amount, dollars(11), "psync quote amount");
      Moonpig->env->process_email_queue;
      Moonpig->env->email_sender->clear_deliveries;
    };
    # At this point, 10 days and $9 remain

    subtest "rate goes down to 18" => sub {
      $c->total_charge_amount(dollars(21));
      elapse($ledger);
      # At this point, 9 days and $7.5 remain
      is(my (@q) = $ledger->quotes, 2, "second psync quote generated");
      $q2 = $q[1];
      ok($q1->is_abandoned, "first quote was automatically abandoned");
      is($q2->total_amount, dollars(6), "new quote amount");
      my $d = get_single_delivery();
    };
    # At this point, 9 days and $7.5 remain

    subtest "rate goes up to 28 again" => sub {
      $c->total_charge_amount(dollars(28));
      elapse($ledger);
      # At this point, 8 days and $5.5 remain
      is(my (@q) = $ledger->quotes, 3, "third psync quote generated");
      $q3 = $q[2];
      ok($q2->is_abandoned, "second quote was automatically abandoned");
      is($q3->total_amount, dollars(10.5), "new quote amount");
      my $d = get_single_delivery();
    };
    # At this point, 8 days and $5.5 remain

    # If it goes down to the amount actually on hand, don't send a quote,
    # just an email.
    subtest "rate goes down to 9.625" => sub {
      # $5.5 / 8 days = $.6875 per day = $9.625 per 14 days
      $c->total_charge_amount(dollars(9.625));
      elapse($ledger);
      # At this point, 7 days and $4.8125 remain
      is(my (@q) = $ledger->quotes, 3, "no fourth psync quote generated");
      ok($q3->is_abandoned, "third quote was automatically abandoned");
      my $d = get_single_delivery();
    };
    # At this point, 7 days and $4.8125 remain

    subtest "rate gets low" => sub {
      $c->total_charge_amount(dollars(0.01));
      elapse($ledger);
      is(my (@q) = $ledger->quotes, 3, "no fourth psync quote generated");
      my $d = get_single_delivery();
    }
  };
};

test "paid and executed" => sub {
  do_test {
    my ($ledger, $c) = @_;
    $c->total_charge_amount(dollars(10));
    elapse($ledger);

    my ($qu) = $ledger->quotes;
    is($qu->total_amount, dollars(3), "psync quote issued for \$3");
    $qu->execute;
    is($c->_predicted_shortfall, 0, "quote executed -> no shortfall");
    ok(! $qu->is_paid, "quote not yet paid");

    my ($credit) = $ledger->add_credit(
      class(qw(Credit::Simulated)),
      { amount => $qu->total_amount },
    );
    elapse($ledger);
    ok($qu->is_paid, "quote is now paid");
    is($c->_predicted_shortfall, 0, "quote paid -> no shortfall");
  };
};

test 'regression' => sub {
  my ($self) = @_;

  do_with_fresh_ledger({ c => { template => 'demo-service',
				minimum_chain_duration => years(6),
			      }}, sub {
    my ($ledger) = @_;

    my $invoice = $ledger->current_invoice;
    $ledger->name_component("initial invoice", $invoice);
    $ledger->heartbeat;

    my $n_invoices = () = $ledger->invoices;
    note "$n_invoices invoice(s)";
    my @quotes = $ledger->quotes;
    note @quotes + 0, " quote(s)";

#    require Data::Dumper;
#    print Data::Dumper::Dumper(ppack($invoice)), "\n";;

    pass();
  });

};

run_me;
done_testing;

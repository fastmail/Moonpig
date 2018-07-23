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

sub elapse {
  my ($ledger, $days) = @_;
  $days //= 1;
  for (1 .. $days) {
    $ledger->heartbeat;
    Moonpig->env->elapse_time(86_400);
  }
}

test 'setup sanity checks' => sub {
  my ($self) = @_;

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
    $self->assert_n_deliveries(1, "invoice");

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
  my ($self) = @_;

  do_test {
    my ($ledger, $c) = @_;
    my $sender = Moonpig->env->email_sender;

    subtest "do not send psync quotes until rate changes" => sub {
      is($c->_predicted_shortfall, 0, "initially no predicted shortfall");
      elapse($ledger);
      is(scalar($ledger->quotes), 0, "no quotes yet");
      elapse($ledger);
      is(scalar($ledger->quotes), 0, "no quotes yet");

      $self->assert_n_deliveries(1, "the invoice");
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
      my ($delivery) = $self->assert_n_deliveries(1, "the psync quote");
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

sub _diag_delivery {
  my ($delivery, $qr) = @_;

  my $email = $delivery->{email};
  use List::AllUtils qw(max);
  my @headers = qw(From To Subject Date);
  my $width = max map {; length } @headers;
  my @lines;
  for my $h (@headers) {
    my @v = $email->header($h);
    if (@v) {
      push @lines, map {; sprintf '%*s: %s', -$width, $h, $_ } @v;
    } else {
      push @lines,        sprintf '%*s: %s', -$width, $h, '(does not appear)';
    }
  }

  diag "+" . "-" x 60 . "+";
  diag join qq{\n}, @lines;

  if ($qr) {
    my ($text) = grep { $_->header('Content-Type') =~ qr{text/plain} }
                 ($email, $email->subparts);
    if ($text and $text->body_str =~ $qr) {
      diag "Found: $1";
    } else {
      diag "Found nothing.";
    }
  }

  return;
}

test 'varying charges' => sub {
  my ($self) = @_;

  do_test {
    my ($ledger, $c) = @_;
    my $sender = Moonpig->env->email_sender;
    my ($q1, $q2, $q3);

    subtest "rate goes up to 28" => sub {
      elapse($ledger, 3);
      $self->assert_n_deliveries(1, "initial invoice");
      $c->total_charge_amount(dollars(28));
      elapse($ledger);
      # At this point, 10 days and $9 remain
      is(($q1) = $ledger->quotes, 1, "first psync quote generated");
      is($q1->total_amount, dollars(11), "psync quote amount");

      $self->assert_n_deliveries(1, "first quote");
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
      $self->assert_n_deliveries(1, "second quote");
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
      $self->assert_n_deliveries(1, "third quote");
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

      $self->assert_n_deliveries(1, "psync notice");
    };
    # At this point, 7 days and $4.8125 remain

    subtest "rate gets low" => sub {
      $c->total_charge_amount(dollars(0.01));
      elapse($ledger);
      is(my (@q) = $ledger->quotes, 3, "no fourth psync quote generated");

      $self->assert_n_deliveries(1, "psync notice");
    }
  };
};

test 'tiny psync' => sub {
  my ($self) = @_;

  # $14 / 14 days is psync template
  #
  do_with_fresh_ledger(
    {
      c => {
        template => 'psync',
        replacement_plan => [ get => '/nothing' ],

        # 25¢ per day, so we can decrease the time by 2-3 days and not hit an
        # extra dollar. -- rjbs, 2013-02-18
        total_charge_amount => dollars(25),
        cost_period => days(100),
        grace_period_duration => days(0),
      }
    },
    sub {
      my ($ledger) = @_;
      my $c = $ledger->get_component("c");
      my ($credit) = $ledger->credit_collection->add({
        type => 'Simulated',
        attributes => { amount => dollars(25) }
      });

      $ledger->name_component("credit", $credit);

      my ($q1);

      subtest 'charge amount goes up by $0.75' => sub {
        elapse($ledger, 3);
        $self->assert_n_deliveries(1, "initial invoice");
        $c->total_charge_amount(dollars(25.75));
        elapse($ledger);
        # At this point, 10 days and $9 remain
        is(($q1) = $ledger->quotes, 1, "psync quote generated...");

        $self->assert_n_deliveries(0, "...but no quote sent");
      };

      subtest 'charge amount goes up by another $0.75' => sub {
        elapse($ledger, 3);
        $c->total_charge_amount(dollars(26.50));
        elapse($ledger);
        # At this point, 10 days and $9 remain
        is(($q1) = $ledger->quotes, 2, "another psync quote generated");

        $self->assert_n_deliveries(1, "...and quote sent");
      };
    }
  );
};

test "paid and executed" => sub {
  my ($self) = @_;

  do_test {
    my ($ledger, $c) = @_;
    elapse($ledger, 3);
    $self->assert_n_deliveries(1, "invoice");
    $c->total_charge_amount(dollars(28));
    elapse($ledger, 1);
    $self->assert_n_deliveries(1, "psync notice");
    # At this point, 10 days and $9 remain

    my ($qu) = $ledger->quotes;
    is($qu->total_amount, dollars(11), "psync quote issued for \$11");
    $qu->execute;
    is($c->_predicted_shortfall, 0, "quote executed -> no shortfall");
    ok(! $qu->is_paid, "quote not yet paid");

    my ($credit) = $ledger->add_credit(
      class(qw(Credit::Simulated)),
      { amount => $qu->total_amount },
    );
    $ledger->process_credits; # not cheating; the POSTable add does this

    elapse($ledger);
    $self->assert_n_deliveries(1, "psync notice (back to zero)");
    ok($qu->is_paid, "quote is now paid");
    is($c->_predicted_shortfall, 0, "quote paid -> no shortfall");
  };
};

test 'reinvoice' => sub {
  my ($self) = @_;

  do_with_fresh_ledger(
    {
      c => { template => 'psync' }
    },
    sub {
      my ($ledger) = @_;
      my $c = $ledger->get_component("c");

      $ledger->credit_collection->add({
        type => 'Simulated',
        attributes => { amount => dollars(14) }
      });

      $ledger->heartbeat;

      $self->assert_n_deliveries(1, "initial invoice (paid)");

      subtest "initial state" => sub {
        my @quotes = $ledger->quotes;
        is(@quotes, 0, "no quotes so far");

        my @payable = $ledger->payable_invoices;
        is(@payable, 0, "we have no payable invoices");

        is($ledger->amount_due, 0, 'we owe nothing');
      };

      my $d = $c->build_and_install_replacement;
      $ledger->heartbeat;

      my $old_invoice_guid;
      subtest "invoice for first replacement" => sub {
        my @payable = $ledger->payable_invoices;
        is(@payable, 1, "we have one payable invoice");
        is($payable[0]->total_amount, dollars(14), "...for \$14");
        $old_invoice_guid = $payable[0]->guid;

        is($ledger->amount_due, dollars(14), 'we owe $14');

        my @quotes = $ledger->quotes;
        is(@quotes, 0, "no quotes so far");

        $self->assert_n_deliveries(1, "first invoice for replacement");
      };

      subtest 'first increase in charge amount' => sub {
        my $second_invoice_guid;
        for (1, 2) {
          $c->total_charge_amount(dollars(16));
          $d->total_charge_amount(dollars(16));

          for (1, 2) {
            # 2 shows that we only reinvoice ONCE not twice
            $ledger->heartbeat;
          }

          $ledger->perform_dunning;

          # When reinvoicing, the shortfall on $c is ignored, because $d will
          # reinvoice.  This change made today (2014-03-11) will prevent users
          # from restoring their old expiration date in cases of reinvoicing,
          # but will also protect them from normally-optional psync charges
          # from becoming mandatory in these cases.
          is($ledger->amount_due, dollars(16), 'we now owe $16');

          my @payable = $ledger->payable_invoices;
          is(@payable, 1, "we have one payable invoice");
          is($payable[0]->total_amount, dollars(16), "...for \$16");

          if (defined $second_invoice_guid) {
            is(
              $payable[0]->guid,
              $second_invoice_guid,
              "we didn't re-reinvoice",
            );

            $self->assert_n_deliveries(0, "...or send mail");
          } else {
            $second_invoice_guid = $payable[0]->guid;
            # seems impossible:
            isnt(
              $second_invoice_guid,
              $old_invoice_guid,
              "...it isn't the initial invoice",
            );

            $self->assert_n_deliveries(1, "second invoice for replacement");
          }

          my @quotes = $ledger->quotes;
          is(@quotes, 0, "no quotes so far");
        }
      };

      subtest "second increase in charge amount" => sub {
        $c->total_charge_amount(dollars(20));
        $d->total_charge_amount(dollars(20));
        $ledger->heartbeat;

        is($ledger->amount_due, dollars(20), 'we now owe $20');

        my @payable = $ledger->payable_invoices;
        is(@payable, 1, "we have one payable invoice");
        is($payable[0]->total_amount, dollars(20), "...for \$20");

        my @quotes = $ledger->quotes;
        is(@quotes, 0, "no quotes so far");

        $self->assert_n_deliveries(1, "third invoice for replacement");
      };

      subtest "decrease in charge amount" => sub {
        $c->total_charge_amount(dollars(12));
        $d->total_charge_amount(dollars(12));
        $ledger->heartbeat;

        is($ledger->amount_due, dollars(12), 'we now owe $12');

        my @payable = $ledger->payable_invoices;
        is(@payable, 1, "we have one payable invoice");
        is($payable[0]->total_amount, dollars(12), '...for $12');

        my @quotes = $ledger->quotes;
        is(@quotes, 0, "no quotes so far");

        $self->assert_n_deliveries(1, "fourth invoice for replacement");
      };

      subtest "paying off the new invoice" => sub {
        $ledger->add_credit(
          class(qw(Credit::Simulated)),
          { amount => dollars(12) },
        );
        $ledger->process_credits;
        $ledger->heartbeat;

        my @payable = $ledger->payable_invoices;
        is(@payable, 0, "paid off the invoice, it didn't respawn");
      };
    },
  );

  pass;
};

test "don't cancel too fast" => sub {
  my ($self) = @_;

  do_test {
    my ($ledger, $c) = @_;
    elapse($ledger, 10);
    $self->assert_n_deliveries(1, "invoice");

    # At this point, $4 and 4 days remain
    is($c->unapplied_amount, dollars(4), '$4 remain');

    $c->total_charge_amount(dollars(1400));

    # We originally wanted to last 14 days, and lasted 10.  So we need to cover
    # the remaining period, or 4/14th of the new total cost:
    my $expected_charge = dollars(1400) / 14 * 4 # 4/14th of new total cost
                        - $c->unapplied_amount;  # amount on hand
    elapse($ledger, 1);
    $self->assert_n_deliveries(1, "psync notice");
    ok($c->is_active, "consumer still active");
    # At this point, $4 and some small fraction of a day remain

    my ($qu) = $ledger->quotes;
    is($qu->total_amount, $expected_charge, "psync quote issued");
  };
};

test 'pay psync quote with autocharger' => sub {
  my ($self) = @_;

  do_test {
    my ($ledger, $c) = @_;

    subtest "do not send psync quotes until rate changes" => sub {
      is($c->_predicted_shortfall, 0, "initially no predicted shortfall");
      elapse($ledger);
      is(scalar($ledger->quotes), 0, "no quotes yet");
      elapse($ledger);
      is(scalar($ledger->quotes), 0, "no quotes yet");

      $self->assert_n_deliveries(1, "the invoice");
    };

    # At this point, 12 days and $12 remain
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

    $ledger->setup_autocharger_from_template(moonpay => {
      amount_available => dollars(100),
    });

    my @payable = $ledger->payable_invoices;
    is(@payable, 0, "we have no payable invoices");

    my $credit = $ledger->autocharge_amount_due({
      quote_guid => $qu->guid,
    });

    is($credit->{amount}, dollars(11), 'we paid our psync quote');

    ok(! $ledger->quotes, 'ledger has no more quotes');

    $self->assert_n_deliveries(1, "mail sent");
  };
};

run_me;
done_testing;

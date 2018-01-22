use Test::Routine;
use Test::More;
use Test::Routine::Util;
use Test::Fatal;

use t::lib::TestEnv;

use Moonpig::Util qw(class days dollars);

with(
  't::lib::Factory::EventHandler',
  'Moonpig::Test::Role::LedgerTester',
);

use Moonpig::Logger::Test;
use Moonpig::Test::Factory qw(do_with_fresh_ledger);

test 'basic' => sub {
  my ($self) = @_;
  do_with_fresh_ledger({},
    sub {
      my ($ledger) = @_;
      my $q = $ledger->quote_for_new_service(
        { template => 'quick' },
        { xid => "test:A" },
        days(3),
      );
      ok($q, "made quote");
      ok(  $q->is_quote, "it is a quote");

      like(exception { $q->_pay_charges },
           qr/unexecuted quote/,
           "can't pay unexecuted quote");

    SKIP:
      { skip "No longer any easy way to get an open quote", 2;
        like(exception { $q->mark_executed },
             qr/open quote/,
             "can't execute open quote");
        $q->mark_closed;
      }
      $q->mark_executed;

      ok(! $q->is_quote, "it is no longer a quote");

      like(exception { $q->mark_executed },
           qr/cannot change value/,
           "second promotion failed");

  });
};

test execute_and_pay => sub {
  # put a charge on a quote, close and execute it,
  # pay it.
  my ($self) = @_;
  do_with_fresh_ledger({},
    sub {
      my ($ledger) = @_;
      my $q = $self->make_and_check_quote($ledger);
      $q->execute;
      ok($q->is_executed, "q was executed");
      ok($q->is_payable, "q is payable");
      ok(! $q->is_quote, "q is no longer a quote");
      ok($q->first_consumer->is_active, "chain was activated");

      $self->heartbeat_and_send_mail($ledger);
      my @deliveries = $self->assert_n_deliveries(1, "invoice");
      my $email = $deliveries[0]->{email};
      like(
        $email->header('subject'),
        qr{payment is due}i,
        "the email we went is an invoice email",
       );

      {
        my ($part) = grep { $_->content_type =~ m{text/plain} } $email->subparts;
        my $text = $part->body_str;
        my ($due) = $text =~ /^TOTAL DUE:\s*(\S+)/m;
        is($due, '$600.00', "it shows the right total due");
      }
    });

  my $xid = "consumer:test:q";
  # extend existing service
  do_with_fresh_ledger({ c => { template => "quick", xid => $xid } },
    sub {
      my ($ledger) = @_;
      my $q = $ledger->quote_for_extended_service($xid, days(8));
      is($q->total_amount, dollars(400), "quote amount for extended service");
      ok(! $q->first_consumer->is_active, "new consumer not yet active");
      { my $i = 0;
        my $c = $q->first_consumer;
        ++$i, $c = $c->replacement while $c;
        is($i, 4, "chain extension is 4 consumers long");
      }
      $q->execute;
      ok(  $q->isnt_quote, "q is now an invoice");
      ok(! $q->first_consumer->is_active, "but new consumer still not yet active");
      is($ledger->get_component("c")->replacement,
        $q->first_consumer,
        "when active service fails over, it fails over to new extension");
    });
};

test 'inactive chain' => sub {
  my ($self) = @_;
  do_with_fresh_ledger({},
    sub {
      my ($ledger) = @_;
      for my $generator (
        sub {
          $ledger->_add_consumer_chain(
            { template => "quick" },
            { xid => "consumer:test:a" },
            days(10)) },
        sub {
          $ledger->_add_consumer_chain(
            { class => class('Consumer::ByTime::FixedAmountCharge') },
            { xid => "consumer:test:a",
              replacement_plan => [ get => '/consumer-template/quick' ],
              charge_amount => dollars(100),
              charge_description => 'dummy',
              cost_period => days(7),
            },
            days(15)); # 7 + 2 + 2 + 2 + 2 = 15
        }) {
        my @chain = $generator->();
        is(@chain, 5, "5-consumer chain from template");
        { my $OK = 1;
          for (@chain) { $OK &&= ! $_->is_active }
          ok($OK, "all chain members are inactive");
        }
      }
    });
};

sub make_and_check_quote {
  my ($self, $ledger) = @_;
  my $q = $ledger->quote_for_new_service(
    { class => class('Consumer::ByTime::FixedAmountCharge') },
    { xid => "consumer:test:a",
      replacement_plan => [ get => '/consumer-template/quick' ],
      charge_amount => dollars(200),
      charge_description => 'mashed potatoes',
      cost_period => days(7),
    },
    days(15),  # 7 + 2 + 2 + 2 + 2 = 15
  );
  my @chain = ($q->first_consumer, $q->first_consumer->replacement_chain);
  ok ($q->is_quote, "returned a quote");
  ok ($q->is_closed, "quote is closed");
  my @charges = $q->all_charges;
  is (@charges, 5, "five charges");
  is ($q->total_amount, dollars(600), "six hundred dollars");
  is (@chain, 5, "chain has five consumers");

  my $fc = $q->first_consumer;
  is($fc->charge_description, "mashed potatoes", "->first_consumer returns the first consumer");
  {
    ok($fc->guid eq $chain[0]->guid, "first chain value OK");
    my $i = 0;
    while ($fc->has_replacement) {
      $fc = $fc->replacement;
      ok($fc->guid eq $chain[++$i]->guid, "chain value OK");
    }
  }
  return $q;
}

test 'invoice handling' => sub {
  my ($self) = @_;
  do_with_fresh_ledger({},
    sub {
      my ($ledger) = @_;
      $self->make_and_check_quote($ledger);
    });
  do_with_fresh_ledger({ xx => { template => "quick", xid => "consumer:test:c" }},
    sub {
      my ($ledger) = @_;
      die unless $ledger->has_current_invoice and $ledger->current_invoice->has_charges;

      # make sure extraneous charges are not on the quote afterward
      my $q1 = $self->make_and_check_quote($ledger);
      my $q2 = $self->make_and_check_quote($ledger);
      ok($q1->guid ne $q2->guid, "two quotes have different guids");

      my $invoice = $ledger->current_invoice;
      ok(! $invoice->is_quote, "new current invoice is not a quote");
      ok(! $invoice->has_charges, "new current invoice is empty");

      $self->make_and_check_quote($ledger);
  });
};

test 'attachment points and obsolesence' => sub {
  my ($self) = @_;
  do_with_fresh_ledger({ c => { template => 'quick', xid => "test:A" } },
    sub {
      my ($ledger) = @_;
      my $cA = $ledger->get_component("c");
      {
        my $qA = $ledger->quote_for_extended_service(
          "test:A",
          days(3),
         );
        my $qA2 = $ledger->quote_for_extended_service(
          "test:A",
          days(3),
         );

        is($qA->attachment_point_guid, $cA->guid, "quote A's attachment point is cA");
        ok(! $qA->is_obsolete(), "quote A not yet obsolete");
        ok(! $qA2->is_obsolete(), "quote A2 not yet obsolete");
        is(exception { $qA->execute }, undef, "executed quote A");
        my $cA2 = $cA->replacement;

        $cA->expire;
        ok($cA2->is_active, "cA's replacement is active");
        ok($qA2->is_obsolete(), "quote A2 is now obsolete");
        like(exception { $qA2->execute }, qr/obsolete/, "can't execute obsolete quote");

        $cA2->expire;
        ok($qA2->is_obsolete(), "quote A2 is still obsolete");
        like(exception { $qA2->execute }, qr/obsolete/, "still can't execute obsolete quote");

        my $qA3 = $ledger->quote_for_extended_service(
          "test:A",
          days(3),
         );
        ok(! $qA3->is_obsolete(),
           "quote A3 for resuming service is not obsolete");
        is(exception { $qA3->execute }, undef, "executed quote A3");
        isnt($ledger->active_consumer_for_xid("test:A"), undef,
             "service A reactivated via new quote");
      }

      {
        my $qB = $ledger->quote_for_new_service(
          { template => 'quick' },
          { xid => "test:B" },
          days(3),
         );
        my $qB2 = $ledger->quote_for_new_service(
          { template => 'quick' },
          { xid => "test:B" },
          days(3),
         );
        is($qB->attachment_point_guid, undef, "quote B has no attachment point");
        is($qB2->attachment_point_guid, undef, "quote B2 has no attachment point");
        ok(! $qB->is_obsolete(), "quote B not obsolete");
        ok(! $qB2->is_obsolete(), "quote B2 not obsolete");

        $qB->execute;
        ok($qB2->is_obsolete(), "quote B2 obsolete after executing quote B");
        $ledger->active_consumer_for_xid("test:B")->handle_terminate;
        ok(! $qB2->is_obsolete, "quote B2 no longer obsolete after service terminated");
      }
    });
};

run_me;
done_testing;

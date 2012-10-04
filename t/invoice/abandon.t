use Test::Fatal;
use Test::More;
use Test::Routine::Util;
use Test::Routine;

use t::lib::TestEnv;

use Moonpig::Util qw(class days dollars event);

with(
  't::lib::Factory::EventHandler',
  'Moonpig::Test::Role::LedgerTester',
);

use t::lib::Logger;
use Moonpig::Test::Factory qw(do_with_fresh_ledger);

before run_test => sub {
  Moonpig->env->email_sender->clear_deliveries;
};

# Simple charges-carried-forward test: Does the new invoice have only
# the non-abandoned charge? Is the amount right? Is it marked unpaid?
# Is the old one marked abandoned?
test carry_forth => sub {
  do_with_fresh_ledger({ c => { template => 'dummy' } }, sub {
    my ($ledger) = @_;
    my $i1 = $ledger->name_component("first_invoice", $ledger->current_invoice);
    my $c = $ledger->get_component("c");

    # record two charges, abandon one
    for my $charge (1, 2) {
      my $ch = $c->charge_current_invoice({
        description => $charge == 1 ? "abandoned charge" : "retained charge",
        amount      => dollars($charge),
      });
      $ch->mark_abandoned if $charge == 1;
    }
    $i1->mark_closed;

    # We do this weird thing because $invoice->abandon used to mean it, which
    # is really bizarre.  It's not the common case.  I've eliminated ->abandon,
    # for now, but if I re-added it these days, it would mean
    # _without_replacement. -- rjbs, 2012-10-04
    $i1->abandon_with_replacement( $ledger->current_invoice );
    my $i2 = $ledger->current_invoice;

    ok($i1->is_abandoned, "original invoice was abandoned");
    is($i2->total_amount, dollars(2), "correct amount on new ledger");
    ok(! $i1->is_paid, "old ledger unpaid");
    ok(! $i2->is_paid, "new ledger unpaid");
    is($i1->abandoned_in_favor_of, $i2->guid,
       "forward link set properly");
  });
};

sub args {
  my ($n) = @_;
  { charge_amount => dollars(10 * $n),
    replacement_plan => [ get => '/nothing' ],
    xid => "account:fixedexp:$$",
    charge_description => "protection services",
    cost_period => days($n),
  };
}

test service_extended => sub {
  do_with_fresh_ledger({},
    sub {
      my ($ledger) = @_;
      my $c1 = $ledger->add_consumer(
        class("Consumer::ByTime::FixedAmountCharge"),
        args(10));
      my $d = $ledger->add_consumer(
        class("Consumer::Dummy"),
        { replacement_plan => [ get => '/nothing' ],
          xid => "dummy:$$",
        } );

      my $i1 = $ledger->current_invoice;
      $i1->add_charge(
        class(qw(InvoiceCharge))->new({
          description => 'dummy charge',
          amount      => dollars(5),
          consumer    => $d,
        }));
      $i1->mark_closed;
      is ($i1->total_amount, dollars(105), "initial invoice is correct");

      my @invoices = $c1->abandon_all_unpaid_charges or fail();
      is_deeply(\@invoices, [$i1], "abandoned charges on expected invoice");

      $i1->abandon_with_replacement($ledger->current_invoice);

      # Use case 2. Consumer charges for service we don't want; reissue
      # invoice without it. Have charges from multiple consumers.
      my $i2 = $ledger->current_invoice;
      is ($i2->total_amount, dollars(5), "new invoice is correct");

      $c1->mark_superseded;

      # Use case 1: Consumers charges for 1 year of service, but then we
      # want to abandon that charge and replace it with one for 3 years of
      # service.
      my $c2 = $ledger->add_consumer(
        class("Consumer::ByTime::FixedAmountCharge"),
        args(30));
      is ($i2->total_amount, dollars(305), "new invoice is still correct");
      is_deeply([$ledger->payable_invoices], [], "No payable invoices yet");
      $i2->mark_closed;
      is_deeply([$ledger->payable_invoices], [$i2], "Just new invoice is payable");
    }
   );
};

test service_canceled => sub {
  do_with_fresh_ledger({ c => { template => 'dummy' } },
    sub {
      my ($ledger) = @_;
      my $c = $ledger->get_component("c");
      my $i1 = $ledger->current_invoice;
      $i1->add_charge(
        class(qw(InvoiceCharge))->new({
          description => 'dummy charge',
          amount      => dollars(5),
          consumer    => $c,
        }));
      $i1->mark_closed;
      my $i2 = $ledger->current_invoice;
      $i1->cancel;
      ok($i1->is_abandoned, "canceled invoice marked abandoned");
      is($i2->total_amount, 0, "charge was not forward-ported");
      is($i1->abandoned_in_favor_of, undef, "no forward-link");
   });
};

test checks => sub {
  do_with_fresh_ledger({ c => { template => 'dummy' } },
    sub {
      my ($ledger) = @_;
      my $c = $ledger->get_component("c");

      my $gen_invoice = sub {
        my ($do_not_abandon_charge) = @_;
        $ledger->current_invoice->mark_closed;
        my $ch = $c->charge_current_invoice({
          description => "some charge",
          amount => dollars(1),
        });
        $ch->mark_abandoned unless $do_not_abandon_charge;
        return $ledger->current_invoice;
      };

      # Abandoning an open invoice is forbidden
      like(
        exception {
          my $invoice = $gen_invoice->();
          $invoice->abandon_with_replacement($invoice->ledger->current_invoice);
        },
        qr/Can't abandon open invoice/,
        "Can't abandon open invoice",
      );

      # Replacing an abandoned invoice with a closed invoice is forbidden
      like( exception {
        my $a = $gen_invoice->();
        my $b = $gen_invoice->();
        $_->mark_closed for $a, $b;
        $a->abandon_with_replacement($b);
      }, qr/Can't replace.*with closed/,
            "Can't replace abandoned invoice with one already closed");

      # Abandoning a paid invoice is forbidden
      like( exception {
        my $a = $gen_invoice->();
        my $b = $gen_invoice->();
        $a->mark_closed; $a->mark_paid;
        $a->abandon_with_replacement($b);
      }, qr/Can't abandon already-paid/,
            "Can't replace abandoned invoice with one already paid");

      # Abandoning an invoice is only allowed if it contains abandoned charges
      like( exception {
        my $a = $gen_invoice->("don't abandon");
        $a->mark_closed;
        $a->abandon_with_replacement( $a->ledger->current_invoice );
      }, qr/Can't.*with no abandoned charges/,
            "Can't replace invoice with no abandoned charges");
    });
};

run_me;
done_testing;

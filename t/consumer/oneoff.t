use Test::Routine;
use Test::More;
use Test::Routine::Util;
use Test::Fatal;

use utf8;
use t::lib::TestEnv;

use Moonpig::Util qw(class days dollars event years);

with(
  't::lib::Factory::EventHandler',
  'Moonpig::Test::Role::LedgerTester',
);

use t::lib::Logger;
use Moonpig::Test::Factory qw(do_with_fresh_ledger);

test 'zero charge dunning' => sub {
  my ($self) = @_;
  my $guid;

  do_with_fresh_ledger(
    {
      c => {
        template => 'oneoff',
        xid      => 'oneoff:abcdef',
      }
    },
    sub {
      my ($ledger) = @_;
      $guid = $ledger->guid;

      my $invoice = $ledger->current_invoice;
      $ledger->name_component("initial invoice", $invoice);
      ok($invoice->is_open, "invoice is open!");

      $self->heartbeat_and_send_mail($ledger);

      ok($invoice->is_open, "we didn't close the chargeless invoice");
    },
  );

  Moonpig->env->storage->do_with_ledger($guid, sub {
    my ($ledger) = @_;

    my $invoice = $ledger->get_component("initial invoice");
    my ($consumer, @rest) = $ledger->consumers;
    is(@rest, 0, "only one consumer");
    ok($consumer->does('Moonpig::Role::Consumer::OneOff'), "...oneoff consumer");

    $consumer->oneoff_issue_charge({
      amount      => dollars(100),
      description => "bake sale prepayment",
    });

    $self->heartbeat_and_send_mail($ledger);
    $self->assert_n_deliveries(1, "invoice");

    my @charges = $ledger->get_component('c')->all_charges;
    is(@charges, 1, "consumer c has one charge, anyway");
    is($charges[0]->amount, dollars(100), "...for five bucks");

    ok(! $invoice->is_open, "we do close it once there is a charge");

    is($ledger->amount_due, dollars(100), 'amount due: $100');
    is($ledger->amount_available, 0, 'amount available: $0');

    $ledger->add_credit(
      class(qw(Credit::Simulated)),
      {
        amount => dollars(100)
      },
    );

    ok($consumer->is_active, "consumer is still active");
    ok(! $invoice->is_paid, "invoice not paid until we process credits");

    $ledger->process_credits;
    pass("processed credits successfully");

    ok(! $consumer->is_active, "consumer deactivated after payment");
    ok($invoice->is_paid, "invoice paid when we process credits");

    is($ledger->amount_due, 0, 'amount due: $0');
    is($ledger->amount_available, dollars(100), 'amount available: $100');

  });
};

run_me;
done_testing;

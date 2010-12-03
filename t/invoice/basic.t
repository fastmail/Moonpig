use Test::Routine;
use Test::More;
use Test::Routine::Util;

use Moonpig::Charge::Basic;
use Moonpig::Credit::Basic;

use Moonpig::Util qw(dollars);

with(
  't::lib::Factory::Ledger',
  't::lib::Factory::EventHandler',
);

use t::lib::Logger;

test charge_close_and_send => sub {
  my ($self) = @_;

  my $ledger = $self->test_ledger;

  my $send_h = $self->make_event_handler('t::Test');
  $ledger->register_event_handler('send-invoice', 'record', $send_h);

  my $invoice = $ledger->current_invoice;

  my $paid_h = $self->make_event_handler('t::Test');
  $invoice->register_event_handler('invoice-paid', 'record', $paid_h);

  $invoice->add_charge_at(
    Moonpig::Charge::Basic->new({
      description => 'test charge (setup)',
      amount      => dollars(10),
    }),
    'test.charges.setup',
  );

  $invoice->add_charge_at(
    Moonpig::Charge::Basic->new({
      description => 'test charge (maintenance)',
      amount      => dollars(5),
    }),
    'test.charges.maintenance',
  );

  is($invoice->total_amount, dollars(15), "invoice line items tally up");

  $invoice->finalize_and_send;

  my $credit = Moonpig::Credit::Basic->new({
    amount => $invoice->total_amount,
  });

  $ledger->process_credits;

  pass("everything ran to completion without dying");
};

test create_bank_on_payment => sub {
  my ($self) = @_;

  my $ledger = $self->test_ledger;

  my $send_h = $self->make_event_handler('t::Test');
  $ledger->register_event_handler('send-invoice', 'record', $send_h);

  my $consumer = $self->add_consumer_to($ledger);

  my $make_bank_h = $self->make_event_handler(Code => {
    code => sub {
      my ($invoice, $event, $arg) = @_;

      # XXX: We can only assume invoice->total_amount because of current
      # restrictions in our invoice/payment implementation that require that
      # invoice and payment amount are equal.  -- rjbs, 2010-10-29
      my $bank = Moonpig::Bank::Basic->new({
        amount => $invoice->total_amount,
        ledger => $invoice->ledger,
      });

      $ledger->add_bank($bank);

      $consumer->_set_bank($bank);
    },
  });

  is_deeply($ledger->_banks, {}, "there are no banks on our ledger yet");
  ok(! $consumer->has_bank, "...nor on our consumer");

  my $invoice = $ledger->current_invoice;

  my $paid_h = $self->make_event_handler('t::Test');
  $invoice->register_event_handler('invoice-paid', 'bank-it', $make_bank_h);

  $invoice->add_charge_at(
    Moonpig::Charge::Basic->new({
      description => 'test charge (maintenance)',
      amount      => dollars(5),
    }),
    'test.charges.maintenance',
  );

  $invoice->finalize_and_send;

  my $credit = Moonpig::Credit::Basic->new({
    amount => $invoice->total_amount,
  });

  $ledger->add_credit($credit);

  $ledger->process_credits;

  ok($consumer->has_bank, "after applying credit, consumer has bank");

  my $bank = $consumer->bank;
  is(
    $bank->amount,
    $invoice->total_amount,
    "the bank is for the invoice amount",
  );
};

run_me;
done_testing;

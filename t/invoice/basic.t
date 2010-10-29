use Test::Routine;
use Test::More;
use Test::Routine::Util;

use Moonpig::Charge::Basic;
use Moonpig::Payment::Basic;

use Moonpig::Util qw(dollars);

with(
  't::lib::Factory::Ledger',
  't::lib::Factory::EventHandler',
);

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

  my $payment = Moonpig::Payment::Basic->new({
    amount => $invoice->total_amount,
  });

  $invoice->accept_payment($payment);

  pass("everything ran to completion without dying");
};

run_me;
done_testing;

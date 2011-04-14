use Test::Routine;
use Test::More;
use Test::Routine::Util;

use Stick::Util qw(ppack);
use Moonpig::Util qw(class dollars event);

with(
  't::lib::Factory::Ledger',
  't::lib::Factory::EventHandler',
  't::lib::Role::UsesStorage',
);

use t::lib::Logger;

before run_test => sub {
  Moonpig->env->email_sender->clear_deliveries;
};

test charge_close_and_send => sub {
  my ($self) = @_;

  my $ledger = $self->test_ledger;

  my $invoice = $ledger->current_invoice;

  my $paid_h = $self->make_event_handler('t::Test');
  $invoice->register_event_handler('paid', 'default', $paid_h);

  $invoice->add_charge_at(
    {
      description => 'test charge (setup)',
      amount      => dollars(10),
    },
    'test.charges.setup',
  );

  $invoice->add_charge_at(
    {
      description => 'test charge (maintenance)',
      amount      => dollars(5),
    },
    'test.charges.maintenance',
  );

  is($invoice->total_amount, dollars(15), "invoice line items tally up");

  $self->heartbeat_and_send_mail($ledger);

  my @deliveries = Moonpig->env->email_sender->deliveries;
  is(@deliveries, 1, "we went the invoice to the customer");
  my $email = $deliveries[0]->{email};
  like(
    $email->header('subject'),
    qr{payment is due}i,
    "the email we went is an invoice email",
  );

  my $credit = $ledger->add_credit(
    class(qw(Credit::Simulated)),
    {
      amount => $invoice->total_amount,
    },
  );

  $ledger->process_credits;

  ok($invoice->is_paid, "the invoice was marked paid");

  is($credit->unapplied_amount, 0, "the credit has been entirely spent");

  pass("everything ran to completion without dying");
};

test underpayment => sub {
  my ($self) = @_;

  my $ledger = $self->test_ledger;

  my $invoice = $ledger->current_invoice;

  my $paid_h = $self->make_event_handler('t::Test');
  $invoice->register_event_handler('paid', 'default', $paid_h);

  $invoice->add_charge_at(
    {
      description => 'test charge (setup)',
      amount      => dollars(10),
    },
    'test.charges.setup',
  );

  is($invoice->total_amount, dollars(10), "invoice line items tally up");

  $self->heartbeat_and_send_mail($ledger);

  my $credit = $ledger->add_credit(
    class(qw(Credit::Simulated)),
    {
      amount => $invoice->total_amount - 1,
    },
  );

  $ledger->process_credits;

  ok(! $invoice->is_paid, "the invoice could not be paid with underpayment");

  is(
    $credit->unapplied_amount,
    $invoice->total_amount - 1,
    "none of the credit was applied"
  );

  pass("everything ran to completion without dying");
};

test overpayment  => sub {
  my ($self) = @_;

  my $ledger = $self->test_ledger;

  my $invoice = $ledger->current_invoice;

  my $paid_h = $self->make_event_handler('t::Test');
  $invoice->register_event_handler('paid', 'default', $paid_h);

  $invoice->add_charge_at(
    {
      description => 'test charge (setup)',
      amount      => dollars(10),
    },
    'test.charges.setup',
  );

  is($invoice->total_amount, dollars(10), "invoice line items tally up");

  $self->heartbeat_and_send_mail($ledger);

  my $credit = $ledger->add_credit(
    class(qw(Credit::Simulated)),
    {
      amount => $invoice->total_amount + 1,
    },
  );

  $ledger->process_credits;

  ok($invoice->is_paid, "the invoice could be paid with overpayment");

  is(
    $credit->unapplied_amount,
    1,
    "there is 1 unit unapplied in the credit",
  );

  pass("everything ran to completion without dying");
};

test create_bank_on_payment => sub {
  my ($self) = @_;

  my $ledger = $self->test_ledger;

  my $consumer = $self->add_consumer_to($ledger);

  is_deeply($ledger->_banks, {}, "there are no banks on our ledger yet");
  ok(! $consumer->has_bank, "...nor on our consumer");

  my $invoice = $ledger->current_invoice;

  my $charge = class(qw(Charge::Bankable))->new({
    description => 'test charge (maintenance)',
    consumer    => $consumer,
    amount      => dollars(5),
  });

  $invoice->add_charge_at($charge, 'test.charges.maintenance');

  $self->heartbeat_and_send_mail($ledger);

  my $credit = $ledger->add_credit(
    class(qw(Credit::Simulated)),
    {
      amount => $invoice->total_amount,
    },
  );

  $ledger->process_credits;

  ok($consumer->has_bank, "after applying credit, consumer has bank");

  my $bank = $consumer->bank;
  is(
    $bank->amount,
    $invoice->total_amount,
    "the bank is for the invoice amount",
  );
};

test payment_by_two_credits => sub {
  my ($self) = @_;

  my $ledger = $self->test_ledger;

  my $invoice = $ledger->current_invoice;

  my $paid_h = $self->make_event_handler('t::Test');
  $invoice->register_event_handler('paid', 'default', $paid_h);

  $invoice->add_charge_at(
    {
      description => 'test charge (setup)',
      amount      => dollars(10),
    },
    'test.charges.setup',
  );

  is($invoice->total_amount, dollars(10), "invoice line items tally up");

  $self->heartbeat_and_send_mail($ledger);

  my @credits = map {;
    $ledger->add_credit(
      class(qw(Credit::Simulated)),
      { amount => dollars(7) }
    );
  } (0, 1);

  $ledger->process_credits;

  ok($invoice->is_paid, "the invoice could be paid with two available credits");

  my @ordered_credits = sort { $a->unapplied_amount <=> $b->unapplied_amount }
                        @credits;

  is($ordered_credits[0]->unapplied_amount, 0, "we used all of one credit");
  is($ordered_credits[1]->unapplied_amount, dollars(4), "...and part of 2nd");

  pass("everything ran to completion without dying");
};

run_me;
done_testing;

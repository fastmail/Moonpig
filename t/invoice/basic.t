use Test::Routine;
use Test::More;
use Test::Routine::Util;

use t::lib::TestEnv;

use Moonpig::Util qw(class dollars event years);

with(
  't::lib::Factory::EventHandler',
  'Moonpig::Test::Role::UsesStorage',
);

use t::lib::Logger;
use Moonpig::Test::Factory qw(do_with_fresh_ledger);

before run_test => sub {
  Moonpig->env->email_sender->clear_deliveries;
};

test charge_close_and_send => sub {
  my ($self) = @_;
  my $guid;

  do_with_fresh_ledger({ c => { template => 'dummy' }}, sub {
    my ($ledger) = @_;
    $guid = $ledger->guid;

    my $invoice = $ledger->current_invoice;
    $ledger->name_component("initial invoice", $invoice);

    my $paid_h = $self->make_event_handler('t::Test');
    $invoice->register_event_handler('paid', 'default', $paid_h);

    $invoice->add_charge(
      class(qw(InvoiceCharge))->new({
        description => 'test charge (setup)',
        amount      => dollars(10),
        consumer    => $ledger->get_component('c'),
      }),
     );

    $invoice->add_charge(
      class(qw(InvoiceCharge))->new({
        description => 'test charge (maintenance)',
        amount      => dollars(5),
        consumer    => $ledger->get_component('c'),
      }),
     );

    is($invoice->total_amount, dollars(15), "invoice line items tally up");

    $self->heartbeat_and_send_mail($ledger);
  });

  my @deliveries = Moonpig->env->email_sender->deliveries;
  is(@deliveries, 1, "we sent the invoice to the customer");
  my $email = $deliveries[0]->{email};
  like(
    $email->header('subject'),
    qr{payment is due}i,
    "the email we went is an invoice email",
   );

  Moonpig->env->storage->do_with_ledger($guid, sub {
    my ($ledger) = @_;

    my $invoice = $ledger->get_component("initial invoice");

    my $credit = $ledger->add_credit(
      class(qw(Credit::Simulated)),
      {
        amount => $invoice->total_amount,
      },
     );

    $ledger->process_credits;

    ok($invoice->is_paid, "the invoice was marked paid");

    is($credit->unapplied_amount, 0, "the credit has been entirely spent");
  });

  pass("everything ran to completion without dying");
};

test underpayment => sub {
  my ($self) = @_;

  do_with_fresh_ledger({ c => { template => 'dummy' }}, sub {
    my ($ledger) = @_;

    my $invoice = $ledger->current_invoice;

    my $paid_h = $self->make_event_handler('t::Test');
    $invoice->register_event_handler('paid', 'default', $paid_h);

    $invoice->add_charge(
      class(qw(InvoiceCharge))->new({
        description => 'test charge (setup)',
        amount      => dollars(10),
        consumer    => $ledger->get_component('c'),
      }),
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
  });

  pass("everything ran to completion without dying");
};

test overpayment  => sub {
  my ($self) = @_;

  do_with_fresh_ledger({ c => { template => 'dummy' }}, sub {
    my ($ledger) = @_;

    my $invoice = $ledger->current_invoice;

    my $paid_h = $self->make_event_handler('t::Test');
    $invoice->register_event_handler('paid', 'default', $paid_h);

    $invoice->add_charge(
      class(qw(InvoiceCharge))->new({
        description => 'test charge (setup)',
        amount      => dollars(10),
        consumer    => $ledger->get_component('c'),
      }),
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
  });

  pass("everything ran to completion without dying");
};

test get_paid_on_payment => sub {
  my ($self) = @_;

  do_with_fresh_ledger({ c => { template => 'dummy_with_bank' }}, sub {
    my ($ledger) = @_;

    my $consumer = $ledger->get_component('c');
    $ledger->save;

    is($consumer->unapplied_amount, 0, "no money in our consumer yet");

    my $invoice = $ledger->current_invoice;

    my $charge = class(qw(InvoiceCharge::Bankable))->new({
      description => 'test charge (maintenance)',
      consumer    => $consumer,
      amount      => dollars(5),
      # tags => [ 'test.charges.maintenance' ],
    });

    $invoice->add_charge($charge);

    $self->heartbeat_and_send_mail($ledger);

    my $credit = $ledger->add_credit(
      class(qw(Credit::Simulated)),
      {
        amount => $invoice->total_amount,
      },
     );

    $ledger->process_credits;

    is(
      $consumer->unapplied_amount,
      $invoice->total_amount,
      "after processing credits, consumer is funded",
    );
  });
};

test payment_by_two_credits => sub {
  my ($self) = @_;

  do_with_fresh_ledger({ c => { template => 'dummy' }}, sub {
    my ($ledger) = @_;

    my $invoice = $ledger->current_invoice;

    my $paid_h = $self->make_event_handler('t::Test');
    $invoice->register_event_handler('paid', 'default', $paid_h);

    $invoice->add_charge(
      class(qw(InvoiceCharge))->new({
        description => 'test charge (setup)',
        amount      => dollars(10),
        consumer    => $ledger->get_component('c'),
      }),
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
  });

  pass("everything ran to completion without dying");
};

run_me;
done_testing;

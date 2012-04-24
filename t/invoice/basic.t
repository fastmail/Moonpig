use Test::Routine;
use Test::More;
use Test::Routine::Util;
use Test::Fatal;

use t::lib::TestEnv;

use Moonpig::Util qw(class dollars event years);

with(
  't::lib::Factory::EventHandler',
  'Moonpig::Test::Role::LedgerTester',
);

use t::lib::Logger;
use Moonpig::Test::Factory qw(do_with_fresh_ledger);

before run_test => sub {
  Moonpig->env->email_sender->clear_deliveries;
};

test 'zero charge dunning' => sub {
  my ($self) = @_;
  my $guid;

  do_with_fresh_ledger({ c => { template => 'dummy' }}, sub {
    my ($ledger) = @_;
    $guid = $ledger->guid;

    my $invoice = $ledger->current_invoice;
    $ledger->name_component("initial invoice", $invoice);
    ok($invoice->is_open, "invoice is open!");

    $self->heartbeat_and_send_mail($ledger);

    ok($invoice->is_open, "we didn't close the chargeless invoice");
  });


  Moonpig->env->storage->do_with_ledger($guid, sub {
    my ($ledger) = @_;

    my $invoice = $ledger->get_component("initial invoice");
    $invoice->add_charge(
      class(qw(InvoiceCharge))->new({
        description => 'test charge (maintenance)',
        amount      => dollars(5),
        consumer    => $ledger->get_component('c'),
      }),
    );

    $self->heartbeat_and_send_mail($ledger);

    my @charges = $ledger->get_component('c')->all_charges;
    is(@charges, 1, "consumer c has one charge, anyway");
    is($charges[0]->amount, dollars(5), "...for five bucks");

    ok(! $invoice->is_open, "we do close it once there is a charge");
  });
};

test 'charge close and send' => sub {
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

  {
    my $msg_id = $email->header('Message-ID') =~ s/\A<|>\z//gr;
    my ($local, $domain) = split /\@/, $msg_id;
    my ($ident) = split /\./, $local;
    is($ident, $guid, "the message id refers to the ledger");
  }

  {
    my ($part) = grep { $_->content_type =~ m{text/plain} } $email->subparts;
    my $text = $part->body_str;
    my ($due) = $text =~ /^TOTAL DUE:\s*(\S+)/m;
    is($due, '$15.00', "it shows the right total due");
  }

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

test 'send with balance on hand' => sub {
  my ($self) = @_;
  my $guid;

  do_with_fresh_ledger({ c => { template => 'dummy' }}, sub {
    my ($ledger) = @_;
    $guid = $ledger->guid;

    my $invoice = $ledger->current_invoice;
    $ledger->name_component("initial invoice", $invoice);

    for (qw(5 10)) {
      $invoice->add_charge(
        class(qw(InvoiceCharge))->new({
          description => 'test charge (setup)',
          amount      => dollars($_),
          consumer    => $ledger->get_component('c'),
        }),
       );
     }

    $ledger->add_credit(
      class(qw(Credit::Simulated)),
      {
        amount => dollars(7)
      },
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

  {
    my ($part) = grep { $_->content_type =~ m{text/plain} } $email->subparts;
    my $text = $part->body_str;
    my ($due) = $text =~ /^TOTAL DUE:\s*(\S+)/m;
    is($due, '$8.00', "it shows the right total due (15 - 7 avail = 8)");
  }

  Moonpig->env->storage->do_with_ledger($guid, sub {
    my ($ledger) = @_;

    my $invoice = $ledger->get_component("initial invoice");

    my $credit = $ledger->add_credit(
      class(qw(Credit::Simulated)),
      {
        amount => dollars(8),
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

test 'get paid on payment' => sub {
  my ($self) = @_;

  do_with_fresh_ledger({ c => { template => 'dummy' }}, sub {
    my ($ledger) = @_;

    my $consumer = $ledger->get_component('c');
    $ledger->save;

    is($consumer->unapplied_amount, 0, "no money in our consumer yet");

    my $invoice = $ledger->current_invoice;

    my $charge = class(qw(InvoiceCharge))->new({
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

test 'payment by two credits' => sub {
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

sub assert_current_invoice_is_not_quote {
  my ($self, $ledger) = @_;
  my $invoice = $ledger->current_invoice;

  ok(  $invoice->isnt_quote, "current invoice is not a quote");
  ok(! $invoice->is_quote, "current invoice is not a quote");
  ok(! $invoice->can('mark_executed'), "can't execute non-quote invoice");
}

test 'quote-related' => sub {
  my ($self) = @_;
  do_with_fresh_ledger(
    {
      c => { template => 'yearly', make_active => 1 },
    },
    sub {
      my ($ledger) = @_;

      $self->assert_current_invoice_is_not_quote($ledger);

      # Make sure that getting a quote doesn't leave a quote in
      # current_invoices;
      my $c = $ledger->get_component('c');
      my $q = $ledger->quote_for_extended_service($c->xid, years(2));

      $self->assert_current_invoice_is_not_quote($ledger);

      $ledger->perform_dunning;

      is($ledger->amount_due, dollars(100), 'we owe $100 (inv, not quote)');

      my @invoices = $ledger->payable_invoices;
      is(@invoices, 1, "we have one payable invoice");
    },
  );
};

run_me;
done_testing;

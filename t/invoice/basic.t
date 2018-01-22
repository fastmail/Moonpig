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

use Moonpig::Logger::Test;
use Moonpig::Test::Factory qw(do_with_fresh_ledger);

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
    $self->assert_n_deliveries(1, "invoice");

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

    no warnings 'redefine';
    local *Moonpig::MKits::assemble_kit = sub {
      my ($self, $kitname, $arg) = @_;

      my $kit = $self->_kit_for($kitname, $arg);
      my $email = $kit->assemble($arg);
      $email->header_set(From => 'set-from@example.com');
      $email->header_set(To   => 'set-to@example.com');

      return $email;
    };

    $self->heartbeat_and_send_mail($ledger);
  });

  my ($delivery) = $self->assert_n_deliveries(1, "the invoice");
  my $email = $delivery->{email};

  like(
    $email->header('subject'),
    qr{payment is due}i,
    "the email we went is an invoice email",
   );

  is(
    $email->header('Moonpig-MKit'),
    Digest::MD5::md5_hex('invoice'),
    "the message indicates its source template",
  );

  is_deeply(
    $delivery->{envelope},
    { from => 'set-from@example.com', to => [ 'set-to@example.com' ] },
    'envelope comes from headers when not given',
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

    my $credit = $ledger->credit_collection->add({
      type => 'Simulated',
      attributes   => { amount => $invoice->total_amount },
      send_receipt => 1,
    });

    my ($delivery) = $self->assert_n_deliveries(1, "the receipt");

    ok($invoice->is_paid, "the invoice was marked paid");

    is($credit->unapplied_amount, 0, "the credit has been entirely spent");
  });

  pass("everything ran to completion without dying");
};

test 'do not mark too many invoices paid' => sub {
  my ($self) = @_;
  my $guid;

  do_with_fresh_ledger({ y1 => { template => 'yearly' }}, sub {
    my ($ledger) = @_;
    $guid = $ledger->guid;

    my $invoice_1 = $ledger->current_invoice;
    $invoice_1->mark_closed;
    is($invoice_1->total_amount, dollars(100), "first invoice: 100 bucks");

    Moonpig->env->elapse_time( 3600 );

    my $invoice_2 = $ledger->current_invoice;

    isnt($invoice_1->guid, $invoice_2->guid, "we made a new invoice");

    my $y2 = $ledger->add_consumer_from_template(
      yearly => { xid => "test:consumer:c" }
    );

    $invoice_2->mark_closed;
    is($invoice_2->total_amount, dollars(100), "second invoice: 100 bucks");

    $self->heartbeat_and_send_mail($ledger);
    my ($delivery) = $self->assert_n_deliveries(1, "the invoices sent as mail");

    is($ledger->amount_due, dollars(200), "total due: 200 bucks");

    ok( ! $invoice_1->is_paid, "invoice 1: not paid");
    ok( ! $invoice_2->is_paid, "invoice 2: not paid");

    $ledger->add_credit(
      class(qw(Credit::Simulated)),
      {
        amount => dollars(100)
      },
    );

    is($ledger->amount_due, dollars(100), "pay 100 bucks, total due: 100 bucks");

    $ledger->process_credits;

    ok(   $invoice_1->is_paid, "invoice 1: paid");
    ok( ! $invoice_2->is_paid, "invoice 2: not paid");

    is($ledger->amount_due, dollars(100), "pay 100 bucks, total due: 100 bucks");
  });
};

test 'send with balance on hand' => sub {
  my ($self) = @_;
  my $guid;

  my @addrs;

  do_with_fresh_ledger({ c => { template => 'dummy' }}, sub {
    my ($ledger) = @_;
    $guid = $ledger->guid;

    @addrs = $ledger->contact->email_addresses;

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

  my ($delivery) = $self->assert_n_deliveries(1, "the invoice");

  is_deeply(
    $delivery->{envelope},
    {
      from => Moonpig->env->from_email_address_mailbox,
      to   => \@addrs,
    },
    'envelope comes from headers when not given',
  );

  my $email = $delivery->{email};

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
    $self->assert_n_deliveries(1, "invoice");

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
    $self->assert_n_deliveries(1, "invoice");

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
    $self->assert_n_deliveries(1, "invoice");

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
    $self->assert_n_deliveries(1, "invoice");

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
      $self->assert_n_deliveries(1, "invoice");

      is($ledger->amount_due, dollars(100), 'we owe $100 (inv, not quote)');

      my @invoices = $ledger->payable_invoices;
      is(@invoices, 1, "we have one payable invoice");
    },
  );
};

test 'record all dunning attempts' => sub {
  my ($self) = @_;

  do_with_fresh_ledger(
    {
      c => { template => 'yearly', grace_period_duration => days (14) },
    },
    sub {
      my ($ledger) = @_;
      $self->heartbeat_and_send_mail($ledger);
      Moonpig->env->elapse_time( days(9) );
      $self->heartbeat_and_send_mail($ledger);

      my @dunnings = @{ $ledger->_dunning_history };

      $self->assert_n_deliveries(2, "we dunned twice");
      is(@dunnings, 2, "we stored two dunning attempts");
      isnt(
        $dunnings[0]{xid_info}{'test:consumer:c'}{expiration_date},
        undef,
        "we have an exp. date for the test consumer in the dunning",
      );
      is(
        $dunnings[0]{xid_info}{'test:consumer:c'}{expiration_date},
        $dunnings[1]{xid_info}{'test:consumer:c'}{expiration_date},
        "...and it's the same for both attempts",
      );

      isnt(
        $dunnings[0]{dunned_at},
        $dunnings[1]{dunned_at},
        "dunning times are distinct",
      );
    },
  );
};

test 'non-ASCII content in email' => sub {
  my ($self) = @_;
  my $guid;

  my $first = 'Günter';
  my $last  = 'Møppmann';

  do_with_fresh_ledger(
    {
      c => { template => 'dummy' },

      ledger => {
        contact => class('Contact')->new({
          first_name      => $first,
          last_name       => $last,
          phone_book      => { home => 1234567890 },
          email_addresses => [ 'gm@example.com' ],
          address_lines   => [ '123 E. ﾻ Straße.' ],
          city            => 'Townville',
          country         => 'USÃ',
        }),
      },
    },
    sub {
      my ($ledger) = @_;

      my $invoice = $ledger->current_invoice;

      $invoice->add_charge(
        class(qw(InvoiceCharge))->new({
          description => 'test charge (setup)',
          amount      => dollars(10),
          consumer    => $ledger->get_component('c'),
        }),
       );

      $self->heartbeat_and_send_mail($ledger);

      $guid = $ledger->guid;
    }
  );

  my ($delivery) = $self->assert_n_deliveries(1, "the invoice");
  my $email = $delivery->{email};
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
    is($due, '$10.00', "it shows the right total due");

    like($text, qr/\Q$first/, "body contains first name correctly");
    like($text, qr/\Q$last/,  "body contains last name correctly");
  }

  pass("everything ran to completion without dying");
};

test 'contact info coercion' => sub {
  my ($self) = @_;
  my $guid;

  do_with_fresh_ledger(
    {
      c => { template => 'dummy' },

      ledger => {
        contact => class('Contact')->new({
          first_name      => 'Thelonious',
          last_name       => 'Monk',
          phone_book      => { home => 1234567890 },
          email_addresses => [ 'sphere@example.com' ],
          address_lines   => [ '   123 E. 42nd St ', ' Apt. Underground' ],
          city            => 'New York',
          country         => 'USA',
        }),
      },
    },
    sub {
      my ($ledger) = @_;
      my $contact = $ledger->contact_history->[0];

      is(
        $contact->{address_lines}->[0],
        '123 E. 42nd St',
        'trimmed leading/trailing space from address lines'
      );

      is(
        $contact->{address_lines}->[1],
        'Apt. Underground',
        'trimmed leading/trailing space from address lines'
      );

      $ledger->_replace_contact({
        attributes => {
          first_name      => 'Nellie',
          last_name       => 'Monk',
          phone_book      => { home => 1234567890 },
          email_addresses => [ 'crepuscule@example.com' ],
          address_lines   => [ '123 E. 42nd St', '' ],
          city            => 'New York',
          country         => 'USA',
        },
      });

      my $new_contact = $ledger->contact_history->[-1];
      is(
        $new_contact->{first_name},
        'Nellie',
        'replaced a contact'
      );

      is(
        $new_contact->{address_lines}->[1],
        undef,
        'deleted blank address lines'
      );
    }
  );

  pass("everything ran to completion without dying");
};

test 'one-time charging' => sub {
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

    my $invoice = $ledger->current_invoice;

    my $c = $ledger->get_component('c');
    $c->charge_current_invoice({
      description => 'one time charge for bananas',
      amount      => dollars(45),
      roles       => [ 'LineItem::SelfConsuming' ],
    });

    $self->heartbeat_and_send_mail($ledger);
    $self->assert_n_deliveries(1, "invoice");

    my @charges = $ledger->get_component('c')->all_charges;
    is(@charges, 1, "consumer c has one charge, anyway");
    is($charges[0]->amount, dollars(45), "...for five bucks");

    ok(! $invoice->is_open, "we do close it once there is a charge");

    is($c->unapplied_amount, 0, "nothing avail before paying");
    my $amount = $self->pay_amount_due($ledger, dollars(45));
    is($c->unapplied_amount, 0, "nothing avail after paying");
  });
};

test 'autopayment' => sub {
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
    $self->assert_n_deliveries(1, "invoice");

    my @charges = $ledger->get_component('c')->all_charges;
    is(@charges, 1, "consumer c has one charge, anyway");
    is($charges[0]->amount, dollars(5), "...for five bucks");

    ok(! $invoice->is_open, "we do close it once there is a charge");

    my $buck = $ledger->add_credit(
      class(qw(Credit::Simulated)),
      {
        amount => dollars(1)
      },
    );

    # The original implementation of autopay assumed you owed (invoiced amount
    # minus unused credits), which ignored earmarks.  That means that a $1
    # credit that was unapplied but earmarked would mean you didn't charge the
    # full amount when autocharging.  Instead, you'd charge $x - $1, and then
    # later charge the last dollar when the earmarked charge got used.  Stupid!
    # This is now fixed, and this is the test. I was too lazy to actually
    # carefully orchestrate the "credit on hand but earmarked" situation
    # naturally.  -- rjbs, 2016-06-13
    my $class = ref $ledger;
    {
      package TestLedger;
      use Moonpig::Util 'dollars';
      our @ISA = $class;
      sub amount_earmarked { dollars(1) }
    }
    bless $ledger, 'TestLedger';

    is($ledger->amount_due, dollars(5), "...we still owe five bucks");

    $ledger->setup_autocharger_from_template(moonpay => {
      amount_available => dollars(11),
    });

    Moonpig->env->elapse_time( days(9) );

    $self->heartbeat_and_send_mail($ledger);
    $self->assert_n_deliveries(1, "invoice");

    is($ledger->amount_due, dollars(0), "...we autopaid");

    my ($credit) = grep { $_->guid ne $buck->guid } $ledger->credits;
    is($credit->amount, dollars(5), "...with a single five-dollar credit");
    is($ledger->autocharger->amount_available, dollars(6), "...six bucks left");
  });
};

run_me;
done_testing;

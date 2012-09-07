use Test::Routine;
use Test::More;
use Test::Routine::Util;

use t::lib::TestEnv;

use Moonpig::Util qw(class dollars event sumof to_dollars years);

with(
  'Moonpig::Test::Role::LedgerTester',
  't::lib::Routine::XferChain',
);

use Moonpig::Test::Factory qw(do_with_fresh_ledger);

test 'shuffle some credit around, then dissolve it' => sub {
  my ($self) = @_;

  do_with_fresh_ledger(
    { },
    sub {
      my ($ledger) = @_;
      $self->setup_xfers_no_refunds($ledger);
      $ledger->heartbeat;

      my $x = $ledger->get_component('x');
      my $y = $ledger->get_component('y');
      my $credit_a = $ledger->get_component('credit_a');
      my $credit_b = $ledger->get_component('credit_b');

      is($credit_a->unapplied_amount, dollars(2), '$2 left in credit A');
      is($credit_b->unapplied_amount, dollars(7), '$7 left in credit B');

      is_deeply(
        $self->guidify_pairs($credit_a->current_allocation_pairs),
        { $x->guid => dollars(3), $y->guid => dollars(7) },
        "allocations from Credit A",
      );

      is_deeply(
        $self->guidify_pairs($credit_b->current_allocation_pairs),
        { $x->guid => dollars(5) },
        "allocations from Credit B",
      );

      is_deeply(
        $self->guidify_pairs($x->effective_funding_pairs),
        { $credit_a->guid => dollars(3), $credit_b->guid => dollars(5) },
        "fundings for Consumer X",
      );

      is_deeply(
        $self->guidify_pairs($y->effective_funding_pairs),
        { $credit_a->guid => dollars(7) },
        "fundings for Consumer Y",
      );

      my $invoice = $ledger->current_invoice;
      $credit_a->dissolve;
      $self->assert_n_deliveries(1, "re-dunned invoice"); # dissolve dunns

      my ($writeoff) = grep { $_->does('Moonpig::Role::Debit::WriteOff') }
                       $ledger->debits;

      is_deeply(
        $self->guidify_pairs($credit_a->current_allocation_pairs),
        { $writeoff->guid => dollars(12) },
        "allocations from now-written-off Credit A",
      );

      my @charges = sort { $a->amount <=> $b->amount } $invoice->all_charges;

      is(@charges, 2, "two charges were made to recover dissolved funds");
      is($charges[0]->owner_guid, $x->guid, "the smaller one for consumer X");
      is($charges[0]->amount, dollars(3),   "...it wants 3 dollars");
      like($charges[0]->description, qr/replace funds/, "...right desc.");

      is($charges[1]->owner_guid, $y->guid, "the larger one for consumer Y");
      is($charges[1]->amount, dollars(7),   "...it wants 7 dollars");
      like($charges[1]->description, qr/replace funds/, "...right desc.");

      is($credit_a->unapplied_amount, 0, "credit A is exhausted");
    },
  );
};

test 'dissolve a credit that is earmarked but not fully applied' => sub {
  my ($self) = @_;

  my ($ledger_guid, $credit_guid);
  do_with_fresh_ledger(
    { x => { template => 'yearly', minimum_chain_duration => years(5) } },
    sub {
      my ($ledger) = @_;
      $ledger_guid = $ledger->guid;

      $self->heartbeat_and_send_mail($ledger);

      my ($delivery) = $self->assert_n_deliveries(1, "initial invoice");

      my $x = $ledger->get_component('x');

      is($ledger->amount_due, dollars(500), 'we owe $500');
      ok(
        ! $ledger->amount_overearmarked,
        "...but that doesn't mean we are over-earmarked",
      );

      my $credit = $self->pay_payable_invoices($ledger, dollars(500));
      $credit_guid = $credit->guid;

      is_deeply(
        $self->guidify_pairs($credit->current_allocation_pairs),
        {
          $x->guid => dollars(100),
        },
        'we only actually applied $100'
      );

      is($credit->unapplied_amount,   dollars(400), '...$400 remain unspent');
      is($ledger->amount_earmarked,   dollars(400), '...which is earmarked');
      is($ledger->amount_due,           dollars(0), 'nothing is due');
      is($ledger->amount_available,     dollars(0), 'nothing is available');
      is($ledger->amount_overearmarked, dollars(0), 'not overearmarked');

      is_deeply([ $ledger->payable_invoices ], [], "no invoices to pay");
    },
  );

  Moonpig->env->storage->do_with_ledger(
    $ledger_guid,
    sub {
      my ($ledger) = @_;
      my ($credit) = grep { $_->guid eq $credit_guid } $ledger->credits;

      {
        my @payable = $ledger->payable_invoices;
        is(@payable, 0, "no payable invoices before credit dissolution");
      }

      $credit->dissolve;

      is($credit->unapplied_amount,       dollars(0), '...credit is spent');
      is($ledger->amount_earmarked,     dollars(400), '...$400 earmarked');
      is($ledger->amount_due,           dollars(500), '...$500 is due');
      is($ledger->amount_available,       dollars(0), '$0 is available');
      is($ledger->amount_overearmarked, dollars(400), '...$400 overearmarked');

      {
        my @payable = $ledger->payable_invoices;
        is(@payable, 1, "one payable invoice after dissolution");
      }

      my @invoices = $ledger->last_dunned_invoices;
      is(@invoices, 1, "dissolving the credit caused 1 invoice to be dunned");

      my $total = sumof { $_->amount } map {; $_->all_charges } @invoices;
      is($total, dollars(100), 'the invoice charges only total $100...');
    },
  );

  Moonpig->env->storage->do_with_ledger(
    $ledger_guid,
    sub {
      my ($ledger) = @_;

      $self->heartbeat_and_send_mail($ledger);

      my ($delivery) = $self->assert_n_deliveries(1);
      my $email = $delivery->{email};
      like($email->header('subject'), qr{payment is due}i, "...(invoice)...");

      {
        my ($part) = grep { $_->content_type =~ m{text/plain} }
                     $email->subparts;
        my $text = $part->body_str;
        my ($due) = $text =~ /^TOTAL DUE:\s*(\S+)/m;
        is($due, '$500.00', '...and it asks for the total $500');
      }
    }
  );
};

run_me;
done_testing;

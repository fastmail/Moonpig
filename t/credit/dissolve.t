use Test::Routine;
use Test::More;
use Test::Routine::Util;

use t::lib::TestEnv;

use Moonpig::Util qw(class dollars event years);

with(
  'Moonpig::Test::Role::UsesStorage',
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

run_me;
done_testing;

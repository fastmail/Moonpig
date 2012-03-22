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

test 'follow the money' => sub {
  my ($self) = @_;

  do_with_fresh_ledger(
    { },
    sub {
      my ($ledger) = @_;
      $self->setup_xfers_abcxy($ledger);

      my $x = $ledger->get_component('x');
      my $y = $ledger->get_component('y');
      my $credit_a = $ledger->get_component('credit_a');
      my $credit_b = $ledger->get_component('credit_b');
      my $credit_c = $ledger->get_component('credit_c');
      my $refund_1 = $ledger->get_component('refund_1');
      my $refund_2 = $ledger->get_component('refund_2');

      my $a_alloc = $self->guidify_pairs($credit_a->current_allocation_pairs);
      my $b_alloc = $self->guidify_pairs($credit_b->current_allocation_pairs);
      my $c_alloc = $self->guidify_pairs($credit_c->current_allocation_pairs);
      my $x_funds = $self->guidify_pairs($x->effective_funding_pairs);
      my $y_funds = $self->guidify_pairs($y->effective_funding_pairs);

      for my $credit (qw(credit_a credit_b credit_c)) {
        is(
          $ledger->get_component($credit)->unapplied_amount,
          dollars(2),
          "two dollars left in $credit",
        );
      }

      is_deeply(
        $a_alloc,
        { $x->guid => dollars(5), $y->guid => dollars(5) },
        "allocations from Credit A",
      );

      is_deeply(
        $b_alloc,
        { $refund_1->guid => dollars(5), $y->guid => dollars(5) },
        "allocations from Credit B",
      );

      is_deeply(
        $c_alloc,
        { $x->guid => dollars(5), $refund_2->guid => dollars(5) },
        "allocations from Credit C",
      );

      is_deeply(
        $x_funds,
        { $credit_a->guid => dollars(5), $credit_c->guid => dollars(5) },
        "fundings for Consumer X",
      );

      is_deeply(
        $y_funds,
        { $credit_a->guid => dollars(5), $credit_b->guid => dollars(5) },
        "fundings for Consumer Y",
      );
    },
  );
};

run_me;
done_testing;

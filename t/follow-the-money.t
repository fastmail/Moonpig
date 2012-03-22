use Test::Routine;
use Test::More;
use Test::Routine::Util;

use t::lib::TestEnv;

use Moonpig::Util qw(class dollars event years);

with('Moonpig::Test::Role::UsesStorage');

use t::lib::Logger;
use Moonpig::Test::Factory qw(do_with_fresh_ledger);

sub fund {
  my ($self, $credit, $consumer, $amount) = @_;
  $credit->ledger->accountant->create_transfer({
    type => 'consumer_funding',
    from => $credit,
    to   => $consumer,
    amount => $amount,
  });
}

sub cashout {
  my ($self, $consumer, $credit, $amount) = @_;
  $credit->ledger->accountant->create_transfer({
    type => 'cashout',
    from => $consumer,
    to   => $credit,
    amount => $amount,
  });
}

sub refund {
  my ($self, $credit, $amount) = @_;

  my $ledger = $credit->ledger;
  my $refund = $ledger->add_debit(class(qw(Debit::Refund)));

  $ledger->accountant->create_transfer({
    type  => 'debit',
    from  => $credit,
    to    => $refund,
    amount  => $amount,
  });

  return $refund;
}

test 'follow the money' => sub {
  my ($self) = @_;

  do_with_fresh_ledger(
    {
      x => { template => 'dummy' },
      y => { template => 'dummy' },
    },
    sub {
      my ($ledger) = @_;
      my $x = $ledger->get_component('x');
      my $y = $ledger->get_component('y');

      my $credit_a = $ledger->add_credit(
        class('Credit::Simulated'),
        { amount => dollars(10) }
      );

      my $credit_b = $ledger->add_credit(
        class('Credit::Simulated'),
        { amount => dollars(10) }
      );

      my $credit_c = $ledger->add_credit(
        class('Credit::Simulated'),
        { amount => dollars(10) }
      );

      $self->fund   ($credit_a, $x, dollars( 5));
      $self->fund   ($credit_b, $x, dollars( 5));
      $self->fund   ($credit_a, $y, dollars( 5));
      $self->cashout($x, $credit_b, dollars( 5));
      my $r1 = $self->refund ($credit_b, dollars( 5));
      $self->fund   ($credit_b, $y, dollars( 5));
      $self->fund   ($credit_c, $x, dollars(10));
      $self->cashout($x, $credit_c, dollars(10));
      my $r2 = $self->refund ($credit_c, dollars( 5));
      $self->fund   ($credit_c, $x, dollars( 5));

      my $a_allocations = $self->_guidify($credit_a->current_allocation_pairs);
      my $b_allocations = $self->_guidify($credit_b->current_allocation_pairs);
      my $c_allocations = $self->_guidify($credit_c->current_allocation_pairs);
      my $x_fundings    = $self->_guidify($x->effective_funding_pairs);
      my $y_fundings    = $self->_guidify($y->effective_funding_pairs);

      is_deeply(
        $a_allocations,
        { $x->guid => dollars(5), $y->guid => dollars(5) },
        "allocations from Credit A",
      );

      is_deeply(
        $b_allocations,
        { $r1->guid => dollars(5), $y->guid => dollars(5) },
        "allocations from Credit B",
      );

      is_deeply(
        $c_allocations,
        { $x->guid => dollars(5), $r2->guid => dollars(5) },
        "allocations from Credit C",
      );

      is_deeply(
        $x_fundings,
        { $credit_a->guid => dollars(5), $credit_c->guid => dollars(5) },
        "fundings for Consumer X",
      );

      is_deeply(
        $y_fundings,
        { $credit_a->guid => dollars(5), $credit_b->guid => dollars(5) },
        "fundings for Consumer Y",
      );
    },
  );
};

sub _guidify {
  my ($self, @pairs) = @_;
  blessed($_) && ($_ = $_->guid) for @pairs;
  return { @pairs };
}

run_me;
done_testing;

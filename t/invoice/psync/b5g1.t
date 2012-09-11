use Test::Routine;
use Test::More;
use Test::Routine::Util;
use Test::Fatal;

use t::lib::TestEnv;
use Stick::Util qw(ppack);
use List::MoreUtils qw(all);

use Moonpig::Util qw(class days dollars event sumof to_dollars weeks years);

with(
  't::lib::Factory::EventHandler',
  'Moonpig::Test::Role::LedgerTester',
);

use t::lib::ConsumerTemplateSet::Demo;
use t::lib::ConsumerTemplateSet::Test;
use Moonpig::Test::Factory qw(do_with_fresh_ledger);

my $jan1 = Moonpig::DateTime->new( year => 2000, month => 1, day => 1 );

before run_test => sub {
  Moonpig->env->stop_clock_at($jan1);
};

{
  my $i = 0;
  sub next_xid {
    $i++;
    "consumer:b5g1:$i";
  }
}

sub _do_test {
  my ($self, $code) = @_;
  my $xid = next_xid();

  do_with_fresh_ledger(
    {
      b5 => {
        xid      => $xid,
        template => 'b5g1_paid',
        minimum_chain_duration => days(50),
      },
    },
    sub {
      my ($ledger) = @_;

      $ledger->heartbeat;
      pay_unpaid_invoices($ledger, dollars(500));
      $self->assert_n_deliveries(1, "invoice");

      my ($c) = $ledger->get_component('b5');
      my @chain = $c->replacement_chain;
      my $g1 = $chain[-1];
      return $code->($ledger, $c, $g1);
    });
}

sub elapse {
  my ($ledger, $days) = @_;
  $days //= 1;
  for (1 .. $days) {
    $ledger->heartbeat;
    Moonpig->env->elapse_time(86_400);
  }
}

test 'setup sanity checks' => sub {
  my ($self) = @_;
  $self->_do_test(sub {
    my ($ledger, $c, $g) = @_;
    ok($c, "consumer c");
    ok($c->does('Moonpig::Role::Consumer::ByTime'), "consumer c is ByTime");
    ok($c->does("t::lib::Role::Consumer::VaryingCharge"), "consumer c is VaryingCharge");
    { my @chain = ($c, $c->replacement_chain);
      is(@chain, 6, "initial chain length 6");
      is($g, $chain[-1], "consumer g is the right one");
    }

    is($c->unapplied_amount, dollars(100), "head consumer unapplied amount");

    ok($g, "consumer g");
    ok($g->does('Moonpig::Role::Consumer::ByTime'), "consumer g is ByTime");
    ok($g->does("Moonpig::Role::Consumer::SelfFunding"), "consumer g is self-funding");
    is($g->self_funding_credit_amount, dollars(100), "self-funding credit amount is \$100");

    my @qu = $ledger->quotes;
    is(@qu, 0, "no quotes");
  });
};

test 'build quote' => sub {
  my ($self) = @_;
  $self->_do_test(sub {
    my ($ledger, $c, $g) = @_;
    my @chain = ($c, $c->replacement_chain);
    $_->total_charge_amount(dollars(120)) for @chain;
    $c->_maybe_send_psync_quote();
    $self->assert_n_deliveries(1, "psync quote");
    is(my ($q) = $ledger->quotes, 1, "now one quote");
    is(my @ch = $q->all_items, 6, "it has six items");
    is(my ($special) = grep($_->does("Moonpig::Role::LineItem::Active"), @ch), 1,
       "one special item");
    ok($special->does("Moonpig::Role::LineItem::SelfFundingAdjustment"),
       "special item does the right role");
    ok($special->has_tag("moonpig.psync.selffunding"),
       "special item is properly tagged");
    is($special->adjustment_amount, dollars(20), "adjustment amount");
  });
};

test 'adjustment execution' => sub {
  my ($self) = @_;
  $self->_do_test(sub {
    my ($ledger, $c, $g) = @_;
    my @chain = ($c, $c->replacement_chain);
    $_->total_charge_amount(dollars(120)) for @chain;
    $c->_maybe_send_psync_quote();
    $self->assert_n_deliveries(1, "psync quote");
    is(my ($q) = $ledger->quotes, 1, "now one quote");
    is(my ($special) = grep($_->does("Moonpig::Role::LineItem::Active"),
                            $q->all_items),
       1,
       "special item does the right role");
    $q->execute;
    pay_unpaid_invoices($ledger, dollars(100));
    ok($q->is_paid, "quote is executed and paid");
    is($g->self_funding_credit_amount, dollars(120),
       "self-funding credit amount raised to \$120");
  });
};

test 'adjustment amounts' => sub {
  my ($self) = @_;
  for my $days (5, 25, 45, 55) {
    $self->_do_test(sub {
      my ($ledger, $c_, $g) = @_;

      my $c = $c_;
      elapse($ledger, $days);
      $c = $c->replacement until $c->is_active;
      my @chain = ($c, $c->replacement_chain);
      note "after $days days, replacement chain has " . @chain . " consumer(s)\n";
      $_->total_charge_amount(dollars(200)) for @chain;
      $c->_maybe_send_psync_quote();
      if ($days < 50) {
        is(my ($q) = $ledger->quotes, 1, "now one quote");
        $self->assert_n_deliveries(1, "psync quote");
        is(my ($special) = grep($_->does("Moonpig::Role::LineItem::Active"),
                                $q->all_items),
           1,
           "special item does the right role");
        my $x_amount = dollars(100*(1 - $days/50));
        is($special->adjustment_amount, $x_amount, "adjustment amount $x_amount");
      } else {
        is(my ($q) = $ledger->quotes, 0, "no quote generated");
      }
    });
  }
};

test 'long chain' => sub {
  my ($self) = @_;
  do_with_fresh_ledger(
    {
      a => {
        xid      => next_xid(),
        template => 'b5g1_paid',
        minimum_chain_duration => days(30),
      },
    }, sub {
      my ($ledger) = @_;
      my ($z) = my ($a) = $ledger->get_component('a');
      $z = $z->replacement while $z->has_replacement;
      my ($sf, @before, @after);
      subtest "set up long chain" => sub {
        $z->_adjust_replacement_chain(days(60), 1);
        my (@chain) = ($a, $a->replacement_chain);
        is(@chain, 10, "chain of length 10");
        ok($chain[7]->does("Moonpig::Role::Consumer::SelfFunding"),
           "consumer #8 is self-funding");
        $sf = $chain[7];
        @before = @chain[0..6];
        @after  = @chain[8..9];
      };

      $ledger->heartbeat;
      $self->assert_n_deliveries(1, "initial invoice");
      pay_unpaid_invoices($ledger, dollars(900)); # 10 - (1 self funding)

      $_->total_charge_amount(dollars(120)) for @before;
      $_->total_charge_amount(dollars(150)) for @after;
      $a->_maybe_send_psync_quote();
      $self->assert_n_deliveries(1, "psync quote");
      is(my ($q) = $ledger->quotes, 1, "now one quote");
      is(my (@it) = $q->all_items, 10, "it has 10 items");
      is(my ($special) = grep($_->does("Moonpig::Role::LineItem::Active"), @it),
         1,
         "found special item");
      is($special->adjustment_amount, dollars(20), "adjustment amount is \$20");
    });
};

run_me;
done_testing;

sub pay_unpaid_invoices {
  my ($ledger, $expect) = @_;

  my $total = sumof { $_->total_amount } $ledger->payable_invoices;
  if (defined $expect) {
    is(
      $total,
      $expect,
      sprintf("invoices should total \$%.2f", to_dollars($expect)),
    )
  } else {
    note sprintf("Total amount payable: \$%.2f", to_dollars($total));
  }
  $ledger->add_credit(class('Credit::Simulated'), { amount => $total });
  $ledger->process_credits;
}

use Test::Routine;
use Test::More;
use Test::Routine::Util;
use Test::Fatal;

use t::lib::TestEnv;
use Stick::Util qw(ppack);

use Moonpig::Util qw(class days dollars event sumof to_dollars weeks years);

with(
  't::lib::Factory::EventHandler',
  'Moonpig::Test::Role::LedgerTester',
#  'Moonpig::Test::Role::UsesStorage',
);

use t::lib::ConsumerTemplateSet::Demo;
use t::lib::ConsumerTemplateSet::Test;
use Moonpig::Test::Factory qw(do_with_fresh_ledger);

my $jan1 = Moonpig::DateTime->new( year => 2000, month => 1, day => 1 );

my $xid;
{
  my $i = 0;
  before run_test => sub {
    $i++;
    $xid = "consumer:b5g1:$i";
    Moonpig->env->stop_clock_at($jan1);
  };
}

sub do_test (&) {
  my ($code) = @_;
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
  do_test {
    my ($ledger, $c, $g) = @_;
    ok($c);
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

    my @qu = $ledger->quotes;
    is(@qu, 0, "no quotes");
  };
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

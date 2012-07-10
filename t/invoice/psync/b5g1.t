use Test::Routine;
use Test::More;
use Test::Routine::Util;
use Test::Fatal;

use t::lib::TestEnv;
use Stick::Util qw(ppack);

use Moonpig::Util qw(class days dollars event sumof weeks years);

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
      my $total = sumof { $_->total_amount } $ledger->payable_invoices;
      die unless $total == dollars(500);
      my ($credit) = $ledger->credit_collection->add({
        type => 'Simulated',
        attributes => { amount => dollars(500) }
       });
      $ledger->name_component("credit", $credit);
      $ledger->current_invoice->mark_closed;
      $ledger->process_credits;

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

    ok($g);
    ok($g->does('Moonpig::Role::Consumer::ByTime'), "consumer g is ByTime");
    ok($g->does("Moonpig::Role::Consumer::SelfFunding"), "consumer g is self-funding");

    my @qu = $ledger->quotes;
    is(@qu, 0, "no quotes");
  };
};

run_me;
done_testing;

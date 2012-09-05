use strict;
use warnings;

use Moonpig::Util -all;
use Test::More;
use Test::Routine;
use Test::Routine::Util;

use t::lib::TestEnv;

with 'Moonpig::Test::Role::LedgerTester';

use Moonpig::Test::Factory qw(do_with_fresh_ledger);

sub jan { Moonpig::DateTime->new( year => 2000, month => 1, day => $_[0] ) }

before run_test => sub {
  Moonpig->env->stop_clock_at(jan(1));
};

test "replacement_chain_expiration_date" => sub {
  do_with_fresh_ledger({ c => {template => 'quick', bank => dollars(100) }}, sub {
    my ($ledger) = @_;
    my ($c) = $ledger->get_component("c");
    $c->adjust_replacement_chain({ chain_duration => days(2) });
    my $d = $c->replacement;
    subtest "sanity checks on setup" => sub {
      my @chain = ($c, $c->replacement_chain);
      is(@chain, 2, "chain length 2");
      is($c->unapplied_amount, dollars(100), "c fully funded");
      is($c->expiration_date, jan(3), "c will expire on 3 jan");
      is($d->unapplied_amount,            0, "d unfunded");
      is($d->expected_funds({include_unpaid_charges => 1}),
         dollars(100), "d has \$100 unpaid charges");
    };
    is($c->replacement_chain_expiration_date({ include_unpaid_charges => 0 }),
       jan(3), "chain will expire on Jan 3 unless charges are paid");
    is($c->replacement_chain_expiration_date({ include_unpaid_charges => 1 }),
       jan(5), "chain will expire on Jan 5 if charges are paid");
  });
};

run_me;
done_testing;

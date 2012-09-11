use Test::Routine;
use Test::More;
use Test::Routine::Util;
use Test::Fatal;

use t::lib::TestEnv;

use Moonpig::Util qw(class dollars event years);

with(
  'Moonpig::Test::Role::LedgerTester',
);

use t::lib::Logger;
use Moonpig::Test::Factory qw(do_with_fresh_ledger);

test 'pay payable invoices' => sub {
  my ($self) = @_;

  do_with_fresh_ledger({ c => { template => 'yearly' }}, sub {
    my ($ledger) = @_;

    $ledger->heartbeat;
    $self->assert_n_deliveries(1, "invoice");

    my $amount = dollars(75);
    my $cred = $ledger->add_credit(class('Credit::Simulated'),
                                   { amount => $amount });

    my $credit = $self->pay_payable_invoices($ledger);
    is($credit->amount, dollars(25));
  });
};

run_me;
done_testing;

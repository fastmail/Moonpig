use Test::Routine;
use Test::More;
use Test::Routine::Util;

use Moonpig::Util qw(class dollars);

use Moonpig::Context::Test -all, '$Context';

use t::lib::Logger;
use Moonpig::Test::Factory qw(build_ledger);

test pay_and_get_refund => sub {
  my ($self) = @_;

  my $ledger = build_ledger();

  my $credit = $ledger->add_credit(
    class(qw( Credit::Simulated Credit::FromPayment t::Refundable::Test )),
    { amount => dollars(10) }
  );

  ok(
    $credit->DOES('Moonpig::Role::Credit::Refundable'),
    "this simulated payment is refundable",
  );

  $credit->issue_refund;

  is($credit->unapplied_amount, 0, "the credit has been entirely spent");

  my @refunds = $ledger->refunds;
  is(@refunds, 1, "there is now 1 refund");
  is($refunds[0]->amount, $credit->amount, "...for the full amount of credit");

  pass("everything ran to completion without dying");
};

run_me;
done_testing;

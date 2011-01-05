use Test::Routine;
use Test::More;
use Test::Routine::Util;

use Moonpig::Util qw(class dollars);

with(
  't::lib::Factory::Ledger',
);

use t::lib::Logger;

test pay_and_get_refund => sub {
  my ($self) = @_;

  my $ledger = $self->test_ledger;

  my $credit = class(qw(
    Credit::Simulated
    Credit::FromPayment
    t::Refundable::Test
  ))->new({
    amount => dollars(10),
  });

  $ledger->add_credit($credit);

  ok(
    $credit->DOES('Moonpig::Role::Refundable'),
    "this simulated payment is refundable",
  );

  $credit->issue_refund($ledger);

  is($credit->unapplied_amount, 0, "the credit has been entirely spent");

  pass("everything ran to completion without dying");
};

run_me;
done_testing;

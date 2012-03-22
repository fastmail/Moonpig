use Test::Routine;
use Test::More;
use Test::Routine::Util;

use t::lib::TestEnv;
use t::lib::Logger;

use Moonpig::Util qw(class dollars);

use Moonpig::Test::Factory qw(do_with_fresh_ledger);

with('Moonpig::Test::Role::UsesStorage');

test pay_and_get_refund => sub {
  my ($self) = @_;

  my ($ledger_guid, $credit_guid);
  do_with_fresh_ledger({}, sub {
    my ($ledger) = @_;
    $ledger_guid = $ledger->guid;

    my $credit = $ledger->add_credit(
      class(qw( Credit::Simulated t::Refundable::Test )),
      { amount => dollars(10) }
    );

    $credit_guid = $credit->guid;

    ok(
      $credit->DOES('Moonpig::Role::Credit::Refundable'),
      "this simulated payment is refundable",
    );
    ok($credit->is_refundable, "is_refundable method");

    $credit->refund_unapplied_amount;

    is($credit->unapplied_amount, 0, "the credit has been entirely spent");

    my @refunds = $ledger->debits;
    is(@refunds, 1, "there is now 1 refund");
    is($refunds[0]->amount, $credit->amount, "...for the right amount");

    pass("everything ran to completion without dying");
  });

  $self->heartbeat_and_send_mail($ledger_guid);

  my @deliveries = Moonpig->env->email_sender->deliveries;
  my $data = JSON->new->decode( $deliveries[0]->{email}->body_str );

  is($data->{ledger}, $ledger_guid, "refund email refers to right ledger");
  is(
    $data->{payload}{credit}{guid},
    $credit_guid,
    "...and the right credit"
  );
};

run_me;
done_testing;

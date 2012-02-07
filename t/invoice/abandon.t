use Test::Routine;
use Test::More;
use Test::Routine::Util;

use t::lib::TestEnv;

use Moonpig::Util qw(class dollars event years);

with(
  't::lib::Factory::EventHandler',
  'Moonpig::Test::Role::UsesStorage',
);

use t::lib::Logger;
use Moonpig::Test::Factory qw(do_with_fresh_ledger);

before run_test => sub {
  Moonpig->env->email_sender->clear_deliveries;
};

# Simple charges-carried-forward test: Does the new invoice have only
# the non-abandoned charge? Is the amount right? Is it marked unpaid?
# Is the old one marked abandoned?
test carry_forth => sub {
  do_with_fresh_ledger({ c => { template => 'dummy' } }, sub {
    my ($ledger) = @_;
    my $i1 = $ledger->name_component("first_invoice", $ledger->current_invoice);
    my $c = $ledger->get_component("c");

    # record two charges, abandon one
    for my $charge (1, 2) {
      my $ch = $c->build_charge({
        description => $charge == 1 ? "abandoned charge" : "retained charge",
        amount      => dollars($charge),
        tags        => $c->invoice_charge_tags,
        consumer    => $c,
      });
      $i1->add_charge($ch);
      $ch->mark_abandoned if $charge == 1;
    }
    $i1->mark_closed;

    $ledger->abandon_invoice($i1);
    my $i2 = $ledger->current_invoice;

    ok($i1->is_abandoned, "original invoice was abandoned");
    is($i2->amount_due, dollars(2), "correct amount on new ledger");
    ok(! $i1->is_paid, "old ledger unpaid");
    ok(! $i2->is_paid, "new ledger unpaid");
  });
};

# Use case 1: Consumers charges for 1 year of service, but then we
# want to abandon that charge and replace it with one for 3 years of
# service.

test service_extended => sub {
  local $TODO = "Not implemented yet";
  fail();
};

# Use case 2. Consumer charges for service we don't want; reissue
# invoice without it. Have charges from multiple consumers.

test service_cancelled => sub {
  local $TODO = "Not implemented yet";
  fail();
};

test checks => sub {
  local $TODO = "Not implemented yet";
  # Abandoning an open invoice is forbidden
  # Replacing an abandoned invoice with a closed invoice is forbidden
  # Abandoning a paid invoice is forbidden
  # Abadnoning an invoice is only allowed if it contains abandoned charges

  fail();
};

run_me;
done_testing;

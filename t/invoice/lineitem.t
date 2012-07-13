use Test::Routine;
use Test::More;
use Test::Routine::Util;
use Test::Fatal;
use t::lib::TestEnv;

with(
  't::lib::Factory::EventHandler',
  'Moonpig::Test::Role::LedgerTester',
);

use t::lib::Logger;
use Moonpig::Test::Factory qw(do_with_fresh_ledger);
use Moonpig::Util qw(class dollars);

test 'zero amounts' => sub {
  my ($self) = @_;
  my $guid;

  do_with_fresh_ledger({ c => { template => 'dummy' }}, sub {
    my ($ledger) = @_;
    my $c = $ledger->get_component('c');

    for my $method (qw(charge_invoice charge_current_journal)) {
      isnt(exception {
        $c->$method({
          description => "zero",
          amount => 0,
        })
      }, undef, "$method with zero amount");
    }

    my $note = class("LineItem::Note")->new({
      amount => dollars(0),
      description => "lineitem zero",
      consumer => $c,
    });

    ok($note, "zero-amount line item");

    my $discount = class("LineItem::Discount")->new({
      amount => dollars(-18),
      description => "lineitem discount",
      consumer => $c,
    });

    ok($discount, "negative-amount line item");

    my $charge = class("InvoiceCharge")->new({
      amount => dollars(40),
      description => "lineitem",
      consumer => $c,
    });

    $ledger->current_invoice->add_charge($note);
    $ledger->current_invoice->add_charge($discount);
    $ledger->current_invoice->add_charge($charge);

    my @all_items = $ledger->current_invoice->all_items;
    is(@all_items, 3, "added 3 line items to current invoice");

    my @unab_items = $ledger->current_invoice->unabandoned_items;
    is(@unab_items, 3, "...none is abandoned");
    is($ledger->current_invoice->total_amount, dollars(22), "the total is 22");
  });
};

run_me;
done_testing;

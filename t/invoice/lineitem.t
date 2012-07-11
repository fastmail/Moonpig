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

    ok(class("t::TestLineItem")->new({ amount => dollars(0),
                                       description => "lineitem zero",
                                       consumer => $c,
                                     }),
       "zero-amount line item");

    ok(class("t::TestLineItem")->new({ amount => dollars(-1),
                                       description => "lineitem zero",
                                       consumer => $c,
                                     }),
       "negative-amount line item");

    my $line_item = class("t::TestLineItem")->new({ amount => dollars(1),
                                                    description => "lineitem",
                                                    consumer => $c,
                                                  });

    $ledger->current_invoice->add_charge($line_item);
    my @all_items = $ledger->current_invoice->all_items;
    is(@all_items, 1, "added line item to current invoice");
    is($ledger->current_invoice->total_amount, dollars(0), "Line item doesn't count");
  });
};

run_me;
done_testing;

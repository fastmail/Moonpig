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

    my $line_item = class("LineItem")->new({ amount => dollars(1),
                                             description => "lineitem" });
    is($line_item->amount, 0, "LineItem amount overridden to zero");
    $ledger->current_invoice->add_charge($line_item);
    my @all_charges = $ledger->current_invoice->all_charges;
    is(@all_charges, 1, "added line item to current invoice");
  });
};

run_me;
done_testing;

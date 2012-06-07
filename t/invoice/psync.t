use Test::Routine;
use Test::More;
use Test::Routine::Util;
use Test::Fatal;

use t::lib::TestEnv;
use Stick::Util qw(ppack);

use Moonpig::Util qw(class days dollars event years);

with(
  't::lib::Factory::EventHandler',
  'Moonpig::Test::Role::LedgerTester',
);

use t::lib::ConsumerTemplateSet::Demo;
use Moonpig::Test::Factory qw(do_with_fresh_ledger);

before run_test => sub {
  Moonpig->env->email_sender->clear_deliveries;
};

test 'quote' => sub {
  do_with_fresh_ledger({ c => { class => class("t::Consumer::VaryingCharge"),
                                cost_period => days(7),
                                next_charge_amount => dollars(1),
                                replacement_plan => [ get => '/nothing' ],
                              }}, sub {
    my ($ledger) = @_;
    my $c = $ledger->get_component("c");
    ok($c);
    ok($c->does('Moonpig::Role::Consumer::ByTime'));
    ok($c->does("t::lib::Role::Consumer::VaryingCharge"));
  });
};

test 'regression' => sub {
  my ($self) = @_;

  do_with_fresh_ledger({ c => { template => 'demo-service',
				minimum_chain_duration => years(6),
			      }}, sub {
    my ($ledger) = @_;

    my $invoice = $ledger->current_invoice;
    $ledger->name_component("initial invoice", $invoice);
    $ledger->heartbeat;

    my $n_invoices = () = $ledger->invoices;
    note "$n_invoices invoice(s)";
    my @quotes = $ledger->quotes;
    note @quotes + 0, " quote(s)";

#    require Data::Dumper;
#    print Data::Dumper::Dumper(ppack($invoice)), "\n";;

    pass();
  });

};

run_me;
done_testing;

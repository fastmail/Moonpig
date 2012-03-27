use Test::Routine;
use Test::More;
use Test::Routine::Util;
use Test::Fatal;

use t::lib::TestEnv;

use Moonpig::Util qw(class days dollars);

with(
  't::lib::Factory::EventHandler',
  'Moonpig::Test::Role::UsesStorage',
);

use t::lib::Logger;
use Moonpig::Test::Factory qw(do_with_fresh_ledger);

#before run_test => sub {
#  Moonpig->env->email_sender->clear_deliveries;
#};

test 'basic' => sub {
  my ($self) = @_;
  do_with_fresh_ledger({},
    sub {
      my ($ledger) = @_;
      my $q = class("Invoice::Quote")->new({
	 ledger => $ledger,
      });
      ok($q, "made quote");
      ok(  $q->is_quote, "it is a quote");
      ok(! $q->is_invoice, "it is a regular invoice");

      like(exception { $q->_pay_charges },
           qr/unpromoted quote/,
           "can't pay unpromoted quote");

      like(exception { $q->mark_promoted },
           qr/open quote/,
           "can't promote open quote");
      $q->mark_closed;
      $q->mark_promoted;

      ok(! $q->is_quote, "it is no longer a quote");
      ok(  $q->is_invoice, "it is now a regular invoice");

      like(exception { $q->mark_promoted },
           qr/cannot change value/,
           "second promotion failed");

  });
};

test 'inactive chain' => sub {
  my ($self) = @_;
  do_with_fresh_ledger({},
    sub {
      my ($ledger) = @_;
      for my $generator (
        sub {
          $ledger->add_consumer_chain_from_template(
            "quick",
            { xid => "consumer:test:a" },
            days(10)) },
        sub {
          $ledger->add_consumer_chain(
            class('Consumer::ByTime::FixedAmountCharge'),
            { xid => "consumer:test:a",
              replacement_plan => [ get => '/consumer-template/quick' ],
              charge_amount => dollars(100),
              charge_description => 'dummy',
              cost_period => days(7),
            },
            days(15)); # 7 + 2 + 2 + 2 + 2 = 15
        }) {
        my @chain = $generator->();
        is(@chain, 5, "5-consumer chain from template");
        { my $OK = 1;
          for (@chain) { $OK &&= ! $_->is_active }
          ok($OK, "all chain members are inactive");
        }
      }
    });
};

test 'invoice handling' => sub {
  my ($self) = @_;
  do_with_fresh_ledger({},
    sub {
      # push extraneous charges on invoice
      # make sure they are not on the quote afterward

      # The quote should not appear as a payable invoice
      pass("TODO");
  });
};


run_me;
done_testing;

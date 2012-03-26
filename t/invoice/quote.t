use Test::Routine;
use Test::More;
use Test::Routine::Util;
use Test::Fatal;

use t::lib::TestEnv;

use Moonpig::Util qw(class);

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

      $q->mark_promoted;
      ok(! $q->is_quote, "it is no longer a quote");
      ok(  $q->is_invoice, "it is now a regular invoice");

      like(exception { $q->mark_promoted },
           qr/cannot change value/,
           "second promotion failed");
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

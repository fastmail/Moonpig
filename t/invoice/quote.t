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
          $ledger->_add_consumer_chain_from_template(
            "quick",
            { xid => "consumer:test:a" },
            days(10)) },
        sub {
          $ledger->_add_consumer_chain(
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

sub make_and_check_quote {
  my ($self, $ledger) = @_;
  my ($q, @chain) = $ledger->generate_quote_for(
    class('Consumer::ByTime::FixedAmountCharge'),
    { xid => "consumer:test:a",
      replacement_plan => [ get => '/consumer-template/quick' ],
      charge_amount => dollars(200),
      charge_description => 'mashed potatoes',
      cost_period => days(7),
    },
    days(15),  # 7 + 2 + 2 + 2 + 2 = 15
   );
  ok ($q->is_quote, "returned a quote");
  ok ($q->is_closed, "quote is closed");
  my @charges = $q->all_charges;
  is (@charges, 5, "five charges");
  is ($q->total_amount, dollars(600), "six hundred dollars");
  is (@chain, 5, "chain has five consumers");

  my $fc = $q->first_consumer;
  is($fc->charge_description, "mashed potatoes", "->first_consumer returns the first consumer");
  {
    ok($fc->guid eq $chain[0]->guid, "first chain value OK");
    my $i = 0;
    while ($fc->has_replacement) {
      $fc = $fc->replacement;
      ok($fc->guid eq $chain[++$i]->guid, "chain value OK");
    }
  }
  return $q;
}

test 'invoice handling' => sub {
  my ($self) = @_;
  do_with_fresh_ledger({},
    sub {
      my ($ledger) = @_;
      $self->make_and_check_quote($ledger);
    });
  do_with_fresh_ledger({ xx => { template => "quick", xid => "consumer:test:c" }},
    sub {
      my ($ledger) = @_;
      die unless $ledger->has_current_invoice and $ledger->current_invoice->has_charges;

      # make sure extraneous charges are not on the quote afterward
      my $q1 = $self->make_and_check_quote($ledger);
      my $q2 = $self->make_and_check_quote($ledger);
      ok($q1->guid ne $q2->guid, "two quotes have different guids");

      my $invoice = $ledger->current_invoice;
      ok(! $invoice->is_quote, "new current invoice is not a quote");
      ok(! $invoice->has_charges, "new current invoice is empty");

      $self->make_and_check_quote($ledger);
  });
};


run_me;
done_testing;

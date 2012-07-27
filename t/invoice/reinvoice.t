use Test::Routine;
use Test::More;
use Test::Routine::Util;
use Test::Fatal;

use t::lib::TestEnv;
use Stick::Util qw(ppack);

use Moonpig::Util qw(class days dollars event weeks years);

with(
  't::lib::Factory::EventHandler',
  'Moonpig::Test::Role::LedgerTester',
);

use t::lib::ConsumerTemplateSet::Demo;
use t::lib::ConsumerTemplateSet::Test;
use Moonpig::Test::Factory qw(do_with_fresh_ledger);

my $jan1 = Moonpig::DateTime->new( year => 2000, month => 1, day => 1 );

before run_test => sub {
  Moonpig->env->email_sender->clear_deliveries;
  Moonpig->env->stop_clock_at($jan1);
};

test 'reissue unpaid invoice' => sub {
  my ($self) = @_;

  do_with_fresh_ledger(
    {
      c => {
        # psync because it's VaryingCharge, nothing more -- rjbs, 2012-07-26
        template => 'psync',
        grace_period_duration => days(3),
      },
    },
    sub {
      my ($ledger) = @_;
      my $c = $ledger->get_component('c');

      $c->handle_event( event('consumer-create-replacement') );

      Moonpig->env->elapse_time(days(1));
      $ledger->heartbeat;

      {
        my @invoices = $ledger->invoices;

        is(@invoices, 1, "there's one invoice");
        is($invoices[0]->total_amount, dollars(28), "...for expected amount");
        is($ledger->amount_due, dollars(28), "...amount due is correct");
      }

      # Should we determine that it'd be the same and scrap it? -- rjbs,
      # 2012-07-26
      $c->reinvoice_initial_charges;
      $ledger->heartbeat; # to close invoice

      {
        my @invoices = $ledger->invoices;

        is(@invoices, 2, "there are two invoices");
        ok($invoices[0]->is_abandoned, '...we have abandoned the first');
        is($invoices[0]->total_amount, 0, '...and we have zeroed the first');

        ok(! $invoices[1]->is_abandoned, "we haven't abandoned the first");
        is($invoices[1]->total_amount, dollars(28), "...2nd has same amount");

        is($ledger->amount_due, dollars(28), "...amount due is correct");
      }

      $_->total_charge_amount(dollars(10)) for ($c, $c->replacement_chain);
      $c->reinvoice_initial_charges;
      $ledger->heartbeat; # to close invoice

      {
        my @invoices = $ledger->invoices;

        is(@invoices, 3, "there are two invoices");
        for (0 .. 1) {
          ok($invoices[$_]->is_abandoned, "...we have abandoned invoice $_");
          is($invoices[$_]->total_amount, 0, "...and zeroed invoice $_");
        }

        ok(! $invoices[2]->is_abandoned, "we haven't abandoned the first");
        is($invoices[2]->total_amount, dollars(20), "...3rd has new amount");

        is($ledger->amount_due, dollars(20), "...amount due is correct");
      }
    },
  );
};

test 'reissue unpaid invoice charges onto open invoice' => sub {
  my ($self) = @_;

  do_with_fresh_ledger(
    {
      c => {
        # psync because it's VaryingCharge, nothing more -- rjbs, 2012-07-26
        template => 'psync',
        grace_period_duration => days(3),
      },
    },
    sub {
      my ($ledger) = @_;
      my $c = $ledger->get_component('c');

      $c->handle_event( event('consumer-create-replacement') );

      Moonpig->env->elapse_time(days(1));

      {
        my @invoices = $ledger->invoices;

        is(@invoices, 1, "there's one invoice");
        is($invoices[0]->total_amount, dollars(28), "...for expected amount");

        ok($invoices[0]->is_open, "...we left it open");
        is($ledger->amount_due, dollars(0), "...amount due is zero (inv open)");
      }

      $_->total_charge_amount(dollars(10)) for ($c, $c->replacement_chain);
      $c->reinvoice_initial_charges;

      {
        my @invoices = $ledger->invoices;

        is(@invoices, 1, "there is still one invoice");
        ok(! $invoices[0]->is_abandoned, '...we have not abandoned the first');
        is(
          $invoices[0]->total_amount,
          dollars(20),
          '...but its amount has been updated'
        );

        is($ledger->amount_due, dollars(0), "...amount due is still zero");
      }

      # psync because it's VaryingCharge, nothing more -- rjbs, 2012-07-26
      my $c2 = $ledger->add_consumer_from_template(psync => {
        xid => 'test:guid:whatever',
        grace_period_duration => days(3),
      });

      {
        my @invoices = $ledger->invoices;

        is(@invoices, 1, "there is still one invoice");
        is(
          $invoices[0]->total_amount,
          dollars(34),
          '...it now reflects both chains'
        );

        is($ledger->amount_due, dollars(0), "...amount due is still zero");
      }

      $_->total_charge_amount(dollars(12)) for ($c, $c->replacement_chain);
      $c->reinvoice_initial_charges;
      $ledger->heartbeat; # we're done here!

      {
        my @invoices = $ledger->invoices;

        is(@invoices, 1, "there is still one invoice");
        is(
          $invoices[0]->total_amount,
          dollars(38),
          '...it now reflects both chains, updated'
        );

        is($ledger->amount_due, dollars(38), "...and amount due is set");
      }
    },
  );
};

test 'keep original open for some charges, rest onto new' => sub {
  my ($self) = @_;

  do_with_fresh_ledger(
    {
      c1 => {
        # psync because it's VaryingCharge, nothing more -- rjbs, 2012-07-26
        template => 'psync',
        grace_period_duration => days(3),
      },
      c2 => {
        template => 'psync',
        grace_period_duration => days(3),
      },
    },
    sub {
      my ($ledger) = @_;
      my $c1 = $ledger->get_component('c1');
      $c1->handle_event( event('consumer-create-replacement') );
      $ledger->heartbeat;

      {
        my @invoices = $ledger->invoices;

        is(@invoices, 1, "there's one invoice");
        is($invoices[0]->total_amount, dollars(42), "...for expected amount");

        ok($invoices[0]->is_closed, "...and it is closed");
        is($ledger->amount_due, dollars(42), "...amount due is correct");
      }

      $_->total_charge_amount(dollars(10)) for ($c1, $c1->replacement_chain);
      $c1->reinvoice_initial_charges;
      $ledger->heartbeat; # to close new invoice

      {
        my @invoices = $ledger->invoices;

        is(@invoices, 2, "there are two invoices");
        is($invoices[0]->total_amount, dollars(14), "...1st is right");
        ok($invoices[0]->is_closed, "...and it is closed");

        is($invoices[1]->total_amount, dollars(20), "...2nd is right");
        ok($invoices[0]->is_closed, "...and it is closed");

        is($ledger->amount_due, dollars(34), "...amount due is correct");
      }
    },
  );
};

run_me;
done_testing;

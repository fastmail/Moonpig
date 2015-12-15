use strict;
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

use t::lib::ConsumerTemplateSet::Test;
use Moonpig::Test::Factory qw(do_with_fresh_ledger);

my $jan1 = Moonpig::DateTime->new( year => 2000, month => 1, day => 1 );

sub do_test (&) {
  my ($code) = @_;
  do_with_fresh_ledger({ c => { template => 'psync' } }, sub {
    my ($ledger) = @_;
    my $c = $ledger->get_component("c");
    $c->_adjust_replacement_chain(days(28));
    my ($credit) = $ledger->add_credit(
      class(qw(Credit::Simulated)),
      { amount => dollars(42) },
    );

    $ledger->name_component("credit", $credit);
    my $d = $c->replacement;
    $ledger->name_component("d", $d);
    my $e = $d->replacement;
    $ledger->name_component("e", $e);

    $code->($ledger, $c, $d, $e);
  });
}

sub elapse {
  my ($ledger, $days) = @_;
  $days //= 1;
  for (1 .. $days) {
    $ledger->heartbeat;
    Moonpig->env->elapse_time(86_400);
  }
}

test 'setup sanity checks' => sub {
  my ($self) = @_;

  do_test {
    my ($ledger, $c, $d, $e) = @_;
    ok($c);
    ok($c->does('Moonpig::Role::Consumer::ByTime'));
    ok($c->does("t::lib::Role::Consumer::VaryingCharge"));
    is($c->_predicted_shortfall, 0, "initially no predicted shortfall");
    is($c->expected_funds({ include_unpaid_charges => 1 }), dollars(14),
       "expected funds incl unpaid");
    is($c->expected_funds({ include_unpaid_charges => 0 }), 0, "expected funds not incl unpaid");
    is($c->_estimated_remaining_funded_lifetime({ amount => dollars(14) }), days(14),
      "est lifetime 7d");

    { my @chain = $c->replacement_chain;
      is(@chain, 2, "replacement chain length");
      ok(! $chain[0]->is_active, "chain 0 not yet active");
      ok(! $chain[1]->is_active, "chain 1 not yet active");
      ok(  $c->is_active, "initial consumer is active");
      is($d->guid, $chain[0]->guid, "\$d set up");
      is($e->guid, $chain[1]->guid, "\$e set up");
    }

    $ledger->perform_dunning; # close the invoice and process the credit

    is($c->expected_funds({ include_unpaid_charges => 1 }), dollars(14),
       "expected funds incl unpaid");
    is($c->expected_funds({ include_unpaid_charges => 0 }), dollars(14),
       "expected funds not incl unpaid");
    is($c->unapplied_amount, dollars(14), "did not spend any money yet");
    is($c->_predicted_shortfall, 0, "initially no predicted shortfall");

    my @inv = $ledger->invoices;
    is(@inv, 1, "one invoice");
    ok($inv[0]->is_closed, "the invoice is closed");
    ok($inv[0]->is_paid, "the invoice is paid");

    $self->assert_n_deliveries(1, "initial invoice");

    my @qu = $ledger->quotes;
    is(@qu, 0, "no quotes");

  };
};

sub close_enough {
  my ($a, $b, $msg) = @_;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  ok(abs($a - $b) <= 1, $msg) or diag "  want: $b +/- 1\n", "  have: $a";
}

test 'psync chains' => sub {
  my ($self) = @_;

  do_test {
    my ($ledger, $c, $d, $e) = @_;

    $ledger->perform_dunning; # close the invoice and process the credit

    # At this point, 14 days and $14 remain on each of three consumers
    # $14 = $196/42

    subtest "psync quote" => sub {
      $_->total_charge_amount(dollars(20)) for $c, $d, $e;
      # At $20/14 per day, the $14 remaining will be used up in 196/20 days,
      # leaving a shortfall of 14 - 196/20 = 42/10 days.

      for ($c, $d, $e) {
        close_enough(
          $_->_predicted_shortfall,
          days(4.2),
          "extra charge -> shortfall 4.2 days"
        );
      }

      elapse($ledger, 2);

      # At this point, 12 days and $156/14 ~=~ $11.14 remain on $c; $14 remains
      # on $d and $e

      is(my ($qu) = $ledger->quotes, 1, "psync quote generated");
      ok($qu->is_closed, "quote is closed");
      ok($qu->is_psync_quote, "quote is a psync quote");
      is($qu->psync_for_xid, $c->xid, "quote's psync xid is correct");

      is (my (@ch) = $qu->all_charges, 3, "three charges on psync quote");
      subtest "psync charge amounts" => sub {
        is($_->amount, dollars(6)) for @ch;
      };
      is ($qu->total_amount, dollars(18), "psync total amount");
    };

    subtest "psync email" => sub {
      # throw away the invoice.
      my @deliveries = grep
        {$_->{email}->header('Subject') ne "Your expiration date has changed"
      } $self->get_and_clear_deliveries;
      is(@deliveries, 1, "psync quote was emailed");
    };

    subtest "psync quote amounts after some charging" => sub {
      # This is horrible, but I don't want to spend the time to rework this
      # test to generate quotes above $1 right now. -- rjbs, 2013-02-18
      local $Moonpig::Role::Dunner::_minimum_psync_amount = 0;

      $_->total_charge_amount(dollars(14)) for $c, $d, $e;
      # Consumer C has $156/14 left of its original $196/14, enough for 11.143 days
      # at the current rate.
      close_enough($c->_predicted_shortfall, days(0.8571429),
                   "active consumer still has a shortfall");
      is($_->_predicted_shortfall, days(0), "inactive consumers no longer have a shortfall")
        for $d, $e;

      $c->_maybe_send_psync_quote();
      is(my (undef, $qu) = $ledger->quotes, 2, "psync quote generated");
      is (my (@ch) = $qu->all_charges, 1, "one charge on psync quote");
      close_enough ($qu->total_amount, dollars(12/14), "psync total amount");
      $self->assert_n_deliveries(1, "psync quote");
    };

  };

};

# This is analogous to what happens when a pobox-basic customer
# ($20/yr) who has paid three years in advance upgrades their service
# to mailstore ($50/yr) halfway through the first year.
test 'mailstore sorta' => sub {
  my ($self) = @_;

  do_test {
    my ($ledger, $c, $d, $e) = @_;
    elapse($ledger, 7);
    $self->assert_n_deliveries(1, "initial invoice");
    # $c now has 7 days and $7 left; $d and $e have 14 days and $14
    $_->total_charge_amount(dollars(35)) for $c, $d, $e;
    # Now using up $2.50 per day
    #   $c's $7 will last 2.8 days for a shortfall of 4.2 days ($10.50 needed)
    #   $d's $14 will last 5.6 days for a shortfall of 8.4 days ($21 needed)
    #   $e is like $d
    $c->_maybe_send_psync_quote();
    $self->assert_n_deliveries(1, "psync quote");
    is(my ($qu) = $ledger->quotes, 1, "psync quote generated");
    is (my (@ch) = $qu->all_charges, 3, "three charges on psync quote");
    is($ch[0]->amount,  dollars(10.50), "active consumer charge amount");
    is($ch[$_]->amount, dollars(21), "inactive consumer $_ charge amount") for 1, 2;
  };
};

# If there's a shortfall in consumer A, and it's *not* paid for, there
# should *not* be a second notice of the same shortfall when A fails
# over to its successor.
test 'repeat notices' => sub {
  my ($self) = @_;

  do_test {
    my ($ledger, $c, $d, $e) = @_;
    elapse($ledger, 2);
    $self->assert_n_deliveries(1, "initial invoice");
    # At this point, $c has 12 days and $12 left
    $_->total_charge_amount(dollars(20)) for $c, $d, $e;
    # At this point, $c only has enough money to last 8.4 more days
    $c->_maybe_send_psync_quote();
    my @q1 = $ledger->quotes;

    elapse($ledger, 10);
    subtest "sanity check" => sub {
      ok(! $c->is_active, "c is no longer active");
      ok(  $d->is_active, "d is now active");
      ok(! $d->in_grace_period, "d is out of its grace period");
      is(@q1, 1, "there was 1 psync quote");
      $self->assert_n_deliveries(1, "psync quote");
    };

    elapse($ledger, 1);
    is(my (@q2) = $ledger->quotes, 1, "no new psync quote");
    $self->assert_n_deliveries(0, "no psync quote");

    $_->total_charge_amount(dollars(30)) for $c, $d, $e;
    elapse($ledger, 2);
    is(my (@q3) = $ledger->quotes, 2, "new psync quote after fresh rate change");
    $self->assert_n_deliveries(1, "psync quote");
  };
};

run_me;
done_testing;

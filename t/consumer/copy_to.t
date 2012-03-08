use Test::Routine;

use t::lib::TestEnv;
use List::AllUtils qw(part);
use Moonpig::Util qw(class days dollars cents years event);
use Test::More;
use Test::Routine::Util;
use t::lib::ConsumerTemplateSet::Test;

with qw(Moonpig::Test::Role::HasTempdir);
use Moonpig::Test::Factory qw(build_ledger);

my ($A, $B);

around run_test => sub {
  my ($orig, $self, @rest) = @_;

  # We can't use Role::UsesStorage here because the method modifiers
  # occur in the wrong order.
  local $ENV{MOONPIG_STORAGE_ROOT} = $self->tempdir;

  Moonpig->env->storage->do_rw(sub {
    $A = build_ledger()->save->guid();
    $B = build_ledger()->save->guid();
    die if $A eq $B;
  });
  Moonpig->env->stop_clock_at (
    Moonpig::DateTime->new( year => 2000, month => 1, day => 1 ));
  $self->$orig(@rest);
};

test dummy => sub {
  my ($self) = @_;
  Moonpig->env->storage->do_with_ledgers([ $A, $B ], sub {
    my ($ledger_a, $ledger_b) = @_;
    my $consumer = $ledger_a->add_consumer_from_template("dummy", { make_active => 1 });
    my $copy = $consumer->copy_to($ledger_b);
    isnt($consumer, $copy, "copied, not moved");
    isnt($consumer->guid, $copy->guid, "copy has fresh guid");
    isnt($consumer->ident, $copy->ident, "copy has fresh ident");
    is($copy->ledger, $ledger_b, "copy is in ledger b");
    ok($copy->is_active, "copy is active");
    ok(! $consumer->is_active, "original is no longer active");
    is($ledger_b->active_consumer_for_xid($consumer->xid),
       $copy,
       "new ledger found active copy with correct xid");
    is($ledger_a->active_consumer_for_xid($consumer->xid),
       undef,
       "old ledger no longer finds consumer for this xid");

    is_deeply(
      [ $copy->replacement_plan_parts ],
      [ $consumer->replacement_plan_parts ],
      "same replacement_plan",
    );
  });
};

test bytime => sub {
  my ($self) = @_;
  for my $make_active (0, 1) {
    note(($make_active ? "active" : "inactive") . " consumer");
    Moonpig->env->storage->do_with_ledgers([ $A, $B ], sub {
      my ($ledger_a, $ledger_b) = @_;
      my $consumer = $ledger_a->add_consumer(
        class("Consumer::ByTime::FixedAmountCharge"),
        { charge_description => "monkey meat",
        charge_amount => cents(1234),
        cost_period => years(1),
        replacement_lead_time => days(3),
        replacement_plan    => [ get => '/nothing' ],
        xid => "eat:more:possum:$make_active",
        make_active => $make_active,
      });
      my $copy = $consumer->copy_to($ledger_b);
      Moonpig->env->elapse_time( days(1) );
      is($copy->grace_period_duration,
        $consumer->grace_period_duration, "same grace period length");
      is($copy->grace_until,
        $consumer->grace_until, "same grace period");
    });
  }
};

test with_bank => sub {
  my ($self) = @_;

  Moonpig->env->stop_clock_at (
    Moonpig::DateTime->new( year => 2000, month => 1, day => 1 ));

  my $xid = "eat:more:possum";

  my ($ledger_a, $ledger_b);

  my $exp_date_a;

  Moonpig->env->storage->do_with_ledgers([ $A, $B ], sub {
    my ($ledger_a, $ledger_b) = @_;

    my $cons_a = $ledger_a->add_consumer(
      class("Consumer::ByTime::FixedAmountCharge"),
      {
        charge_description => "monkey meat",
        charge_amount => cents(100),
        cost_period => days(100),
        replacement_lead_time => days(3),
        replacement_plan    => [ get => '/nothing' ],
        xid => $xid,
        make_active => 1,
      });
    $ledger_a->name_component("original consumer", $cons_a);

    my $credit = $ledger_a->add_credit(
      class(qw(Credit::Simulated)),
      { amount => dollars(100) },
    );

    $ledger_a->heartbeat;
    $ledger_a->process_credits;

    is($cons_a->unapplied_amount, cents(100), "cons A initially rich");

    $exp_date_a = $cons_a->expiration_date->clone;

    cmp_ok(
      $cons_a->expiration_date, '==',
        Moonpig::DateTime->new( year => 2000, month => 4, day => 10 ),
      "expiration date is 100d post creation"
    );

    Moonpig->env->elapse_time( days(9) );
    $ledger_a->heartbeat;

    cmp_ok(
      $cons_a->expiration_date, '==', $exp_date_a,
      "expiration date is still 100d post creation"
    );

    is($cons_a->unapplied_amount, cents(90), "cons A used up 10% of value");
    my $cons_b = $cons_a->copy_to($ledger_b);
    $ledger_b->name_component("copy consumer", $cons_b);
  });

  Moonpig->env->storage->do_with_ledgers([ $A, $B ], sub {
    my ($ledger_a, $ledger_b) = @_;

    # We do this so that if any invoice is there, open, with charges, it will
    # get closed.  That way we can find it later in the test. -- rjbs,
    # 2012-03-08
    $ledger_b->heartbeat;

    my $cons_a = $ledger_a->get_component("original consumer");
    my $cons_b = $ledger_b->get_component("copy consumer");

    isnt($cons_a->guid, $cons_b->guid, "consumer was copied");

    is($cons_a->unapplied_amount, 0, "all monies transferred out of cons A");
    is($cons_b->unapplied_amount, cents(90),
       "cons B fully funded");

    my @xfers_a = $ledger_a->accountant->from_consumer($cons_a)->all;
    my ($t_xfers, $j_xfers) = part { $_->amount == cents(1) } @xfers_a;
    is(@$j_xfers, 10, "we did 10 normal daily charges");
    is(@$t_xfers,  1, "... and one management transfer xfer");

    is(
      $t_xfers->[0]->target,
      $ledger_a->current_journal,
      "... to the current journal",
    );

    my ($charge_a) = grep { $_->amount != cents(1) }
                     $ledger_a->current_journal->all_charges;

    like($charge_a->description,
         qr/Transfer management of '\Q$xid\E' to ledger \Q$B\E/,
         "...checked its description");

    my ($cred_b, $d1) = $ledger_b->credits;
    ok($cred_b && ! $d1, "found unique credit in target ledger");
    is($cred_b->as_string, "transient credit", "...checked its credit type");
    is($cred_b->amount, cents(90), "credit amount");
    my ($xfer_b, $d2) = $ledger_b->accountant->from_credit($cred_b)->all;
    ok($xfer_b && ! $d2, "found unique credit transfer in target ledger");

    cmp_ok(
      $cons_b->expiration_date, '==', $exp_date_a,
      "expiration date is still 100d post original",
    );
  });
};

test with_replacement => sub {
  my ($self) = @_;
  Moonpig->env->storage->do_with_ledgers([ $A, $B ], sub {
    my ($ledger_a, $ledger_b) = @_;
    my $cons_a = $ledger_a->add_consumer_from_template(
      "dummy",
      { replacement_plan => [ get => "/consumer-template/boring" ] });
    $cons_a->handle_event(
      event("consumer-create-replacement"));
    ok($cons_a->has_replacement, "consumer now has replacement");
    my $repl_a = $cons_a->replacement;
    ok($repl_a->does("Moonpig::Role::Consumer::ByTime"),
       "replacement is as expected");
    is($repl_a->xid, $cons_a->xid, "xids match");
    my $cons_b = $cons_a->copy_to($ledger_b);
    ok($cons_b->has_replacement, "copy has replacement");
    my $repl_b = $cons_b->replacement;
    isnt($repl_a->guid, $repl_b->guid, "copy of replacement is fresh");
    ok(not ($repl_a->is_active xor $repl_b->is_active),
       "replacements activations  match");
    ok($repl_b->does("Moonpig::Role::Consumer::ByTime"),
       "replacement copy is as expected");
  });
};

run_me;
done_testing;

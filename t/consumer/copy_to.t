
use strict;
use Moonpig::Env::Test;
use Moonpig::URI;
use Moonpig::Util qw(class days dollars cents years event);
use Test::More;
use Test::Routine;
use Test::Routine::Util;
use t::lib::ConsumerTemplateSet::Test;

with qw(t::lib::Factory::Ledger
        t::lib::Role::UsesStorage);

my ($ledger_a, $ledger_b, $A, $B);

before run_test => sub {
  my ($self) = @_;
  $_ = $self->test_ledger(class('Ledger'),
                          { contact => $self->random_contact })
    for $ledger_a, $ledger_b;
  $A = $ledger_a->guid;
  $B = $ledger_b->guid;
  die if $A eq $B;
  Moonpig->env->stop_clock_at (
    Moonpig::DateTime->new( year => 2000, month => 1, day => 1 ));
};

test dummy => sub {
  my ($self) = @_;
  my $consumer = $self->add_consumer_to($ledger_a);
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
  is($copy->replacement_mri, $consumer->replacement_mri,
     "same replacement_mri");
};

test bytime => sub {
  my ($self) = @_;
  for my $make_active (0, 1) {
    note(($make_active ? "active" : "inactive") . " consumer");
    my $consumer = $ledger_a->add_consumer(
      class("Consumer::ByTime::FixedCost"),
      { charge_description => "monkey meat",
        charge_path_prefix => [ ],
        cost_amount => cents(1234),
        cost_period => years(1),
        old_age => days(3),
        replacement_mri => Moonpig::URI->nothing,
        xid => "eat:more:possum:$make_active",
        make_active => $make_active,
      });
    my $copy = $consumer->copy_to($ledger_b);
    Moonpig->env->elapse_time( days(1) );
    is($copy->grace_period_duration,
       $consumer->grace_period_duration, "same grace period length");
    is($copy->grace_until,
       $consumer->grace_until, "same grace period");
  }
};

test with_bank => sub {
  my ($self) = @_;
  my $xid = "eat:more:possum";

  my $bank_a = $self->add_bank_to($ledger_a);
  my $cons_a = $self->add_consumer_to($ledger_a,
    { class => class("Consumer::ByTime::FixedCost"),
      bank => $bank_a,

      charge_description => "monkey meat",
      charge_path_prefix => [ ],
      cost_amount => cents(1234),
      cost_period => years(1),
      old_age => days(3),
      replacement_mri => Moonpig::URI->nothing,
      xid => $xid,
      make_active => 1,
    });
  is($cons_a->unapplied_amount, dollars(100), "cons A initially rich");

  my $cons_b = $cons_a->copy_to($ledger_b);
  my $bank_b = $cons_b->bank;
  ok($bank_b, "bank is in new ledger");
  isnt($bank_b->guid, $bank_a->guid, "bank was copied");

  is($cons_a->unapplied_amount, 0, "all monies transferred out of cons A");
  is($cons_b->unapplied_amount, dollars(100),
     "cons B fully funded");

  my ($xfer_a, $d3) = $ledger_a->accountant->from_bank($bank_a)->all;
  ok($xfer_a && ! $d3, "found unique bank transfer in source ledger");
  is($xfer_a->target, $cons_a, "... checked its target");
  my ($charge_a, $d4) = $ledger_a->current_journal->gather_all_charges;
  ok($charge_a && ! $d4, "found unique charge on source ledger");
  like($charge_a->description,
       qr/Transfer management of '\Q$xid\E' to ledger \Q$B\E/,
       "...checked its description");

  my ($cred_b, $d1) = $ledger_b->credits;
  ok($cred_b && ! $d1, "found unique credit in target ledger");
  is($cred_b->as_string, "transient credit", "...checked its credit type");
  is($cred_b->amount, dollars(100), "credit amount");
  my ($xfer_b, $d2) = $ledger_b->accountant->from_credit($cred_b)->all;
  ok($xfer_b && ! $d2, "found unique credit transfer in target ledger");
  my ($invoice_b) = $xfer_b->target;
  ok($invoice_b, "found transient invoice in target ledger");
  cmp_ok($invoice_b->is_paid, "==", 1, "invoice should be paid");
  my ($charge_b, $d5) = $invoice_b->gather_all_charges;
  ok($charge_b && ! $d5, "found unique charge on target invoice from consumer");
  like($charge_b->description,
       qr/Transfer management of '\Q$xid\E' from ledger \Q$A\E/,
       "...checked its description");
};

test with_replacement => sub {
  my ($self) = @_;
  my $cons_a = $self->add_consumer_to(
    $ledger_a,
    { class => class("Consumer::Dummy"),
      replacement_mri => "moonpig://consumer-template/boring" });
  $cons_a->handle_event(
    event("consumer-create-replacement",
          { mri => $cons_a->replacement_mri }));
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
};


run_me;
done_testing;

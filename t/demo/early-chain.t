#!/usr/bin/env perl
use Test::Routine;
use Test::Routine::Util -all;
use Test::More;

use Moonpig::Util qw(years);

with 't::lib::Routine::DemoTest';

after setup_before_big_loop => sub {
  my ($self, $ledger)= @_;

  $self->active_consumer->adjust_replacement_chain({
    chain_length => years(1)
  });
};

after process_daily_assertions => sub {
  my ($self, $day, $ledger) = @_;

  return unless $day == 370;

  # by this time, consumer 1 should've failed over to consumer 2
  my @consumers   = $ledger->consumers;
  my $active      = $self->active_consumer;
  my ($inactive)  = grep { $_->guid ne $active->guid } @consumers;

  is(@consumers, 2, "by day 370, we have created a second consumer");
  is(
    $active->guid,
    $inactive->replacement->guid,
    "the active one is the replacement for the original one",
  );

  my @active_charges   = $active->all_charges;
  my @inactive_charges = $inactive->all_charges;

  is(@active_charges,   2, "the active one has charged once");
  is(@inactive_charges, 2, "the inactive one has charged once, too");
  cmp_ok(
    $active_charges[0]->date, '==', $inactive_charges[0]->date,
    "...inactive and active charged on the same day",
  );
};

after process_daily_assertions => sub {
  my ($self, $day, $ledger) = @_;
  return unless $day == 740;

  # by this time, consumer 2 should've failed over to consumer 3 and expired
  my @consumers   = $ledger->consumers;
  my $active      = $self->active_consumer;

  is(@consumers, 3, "by day 740, we have created a third consumer");
  ok( ! $active,    "...and they are all inactive");
};

run_me({ invoices_to_pay => 1 });
done_testing;

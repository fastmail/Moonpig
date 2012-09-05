#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Test::Fatal;
use Test::Routine;
use Test::Routine::Util -all;
use t::lib::TestEnv;
use Moonpig::Util qw(class dollars);

use Moonpig::Test::Factory qw(build_ledger);
with ('Moonpig::Test::Role::LedgerTester');

test "accessor" => sub {
  my ($self) = @_;

  my $ledger = build_ledger();

  my $r = class("Debit::Refund")->new({
    ledger => $ledger,
  });

  my @refunds = $ledger->debits();
  is(@refunds, 0, "before list");
  is_deeply(\@refunds, $ledger->debit_array, "before array");
  $ledger->add_debit($r);
  @refunds = $ledger->debits();
  is(@refunds, 1, "after list");
  is_deeply(\@refunds, $ledger->debit_array, "after array");
};

test "constructor" => sub {
  my ($self) = @_;
  my $ledger = build_ledger();

  my $c = $ledger->debit_collection;
  ok($c->does("Stick::Role::Collection"));
};

sub refund_amounts {
  join ", " => sort map $_->amount, @_;
}

test "collection object" => sub {
  my ($self) = @_;
  my $ledger = build_ledger();

  my $credit = $ledger->add_credit(
    class('Credit::Simulated', 't::Refundable::Test'),
    { amount => dollars(5_000) },
  );

  my $c = $ledger->debit_collection();
  ok($c);
  ok($c->does("Stick::Role::Collection"));

  my @r;

  for (0..2) {
    $c = $ledger->debit_collection();
    is($c->count, @r, "collection contains $_ refund(s)" );
    is(refund_amounts($c->all), refund_amounts(@r), "amounts are correct");
    last if $_ == 2;
    push @r, my $next_refund = $ledger->add_debit(class('Debit::Refund'));
    $ledger->create_transfer({
      type => 'debit',
      from => $credit,
      to   => $next_refund,
      amount => dollars(10) + $_ * dollars(1.01),
    });
  }
};

test "ledger gc" => sub {
  my ($self) = @_;
  my $ledger = build_ledger();

  my $rc = $ledger->debit_collection();
  ok($rc->owner, "was ledger prematurely garbage-collected?");
};

run_me;
done_testing;

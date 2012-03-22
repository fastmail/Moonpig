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
with ('Moonpig::Test::Role::UsesStorage');

my $Ledger;
before run_test => sub {
  $Ledger = build_ledger();
};

sub refund {
  my ($self) = @_;
  class("Debit::Refund")->new({
    ledger => $Ledger,
  });
}

test "accessor" => sub {
  my ($self) = @_;

  my $r = $self->refund();

  my @refunds = $Ledger->debits();
  is(@refunds, 0, "before list");
  is_deeply(\@refunds, $Ledger->debit_array, "before array");
  $Ledger->add_debit($r);
  @refunds = $Ledger->debits();
  is(@refunds, 1, "after list");
  is_deeply(\@refunds, $Ledger->debit_array, "after array");
};

test "constructor" => sub {
  my ($self) = @_;
  my $c = $Ledger->debit_collection;
  ok($c->does("Stick::Role::Collection"));
};

sub refund_amounts {
  join ", " => sort map $_->amount, @_;
}

test "collection object" => sub {
  my ($self) = @_;
  my $credit = $Ledger->add_credit(
    class('Credit::Simulated', 't::Refundable::Test'),
    { amount => dollars(5_000) },
  );

  my $c = $Ledger->debit_collection();
  ok($c);
  ok($c->does("Stick::Role::Collection"));

  my @r;

  for (0..2) {
    $c = $Ledger->debit_collection();
    is($c->count, @r, "collection contains $_ refund(s)" );
    is(refund_amounts($c->all), refund_amounts(@r), "amounts are correct");
    last if $_ == 2;
    push @r, my $next_refund = $Ledger->add_debit(class('Debit::Refund'));
    $Ledger->create_transfer({
      type => 'debit',
      from => $credit,
      to   => $next_refund,
      amount => dollars(10) + $_ * dollars(1.01),
    });
  }
};

test "ledger gc" => sub {
  my ($self) = @_;
  my $rc = $Ledger->debit_collection();
  undef $Ledger;
  ok($rc->owner, "was ledger prematurely garbage-collected?");
};

run_me;
done_testing;

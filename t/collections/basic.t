#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Test::Fatal;
use Test::Routine;
use Test::Routine::Util -all;
use Moonpig::Env::Test;
use Moonpig::Util qw(class dollars);

use t::lib::Factory qw(build_ledger);
with ('t::lib::Role::UsesStorage');

use Moonpig::Context::Test -all, '$Context';

my $Ledger;
before run_test => sub {
  $Ledger = build_ledger();
};

sub refund {
  my ($self) = @_;
  class("Refund")->new({
    ledger => $Ledger,
  });
}

test "accessor" => sub {
  my ($self) = @_;

  my $r = $self->refund();

  my @refunds = $Ledger->refunds();
  is(@refunds, 0, "before list");
  is_deeply(\@refunds, $Ledger->refund_array, "before array");
  $Ledger->add_refund($r);
  @refunds = $Ledger->refunds();
  is(@refunds, 1, "after list");
  is_deeply(\@refunds, $Ledger->refund_array, "after array");
};

test "constructor" => sub {
  my ($self) = @_;
  my $c = $Ledger->refund_collection;
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

  my $c = $Ledger->refund_collection();
  ok($c);
  ok($c->does("Stick::Role::Collection"));

  my @r;

  for (0..2) {
    $c = $Ledger->refund_collection();
    is($c->count, @r, "collection contains $_ refund(s)" );
    is(refund_amounts($c->all), refund_amounts(@r), "amounts are correct");
    last if $_ == 2;
    push @r, my $next_refund = $Ledger->add_refund(class('Refund'));
    $Ledger->create_transfer({
      type => 'credit_application',
      from => $credit,
      to => $next_refund,
      amount => dollars(10) + $_ * dollars(1.01),
    });
  }

  note "0..2 done, starting 3..5\n";

  for (3..5) {
    $c = $Ledger->refund_collection();
    is($c->count, @r, "collection contains $_ refund(s)" );
    is(refund_amounts($c->all), refund_amounts(@r), "amounts are correct");
    last if $_ == 5;
    push @r, my $next_refund = $c->add();
    $Ledger->create_transfer({
      type => 'credit_application',
      from => $credit,
      to => $next_refund,
      amount => dollars(10) + $_ * dollars(1.01),
    });
  }
};

test "ledger gc" => sub {
  my ($self) = @_;
  my $rc = $Ledger->refund_collection();
  undef $Ledger;
  ok($rc->owner, "was ledger prematurely garbage-collected?");
};

run_me;
done_testing;

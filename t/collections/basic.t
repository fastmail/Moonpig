#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Test::Fatal;
use Test::Routine;
use Test::Routine::Util -all;
use Moonpig::Env::Test;
use Moonpig::Util qw(class dollars);

with(
  't::lib::Factory::Ledger',
);

has ledger => (
  is => 'ro',
  does => 'Moonpig::Role::Ledger',
  lazy => 1,
  default => sub { $_[0]->test_ledger },
  clearer => 'scrub_ledger',
);

before run_test => sub {
  my ($self) = @_;

  $self->scrub_ledger;
};

sub refund {
  my ($self) = @_;
  class("Refund")->new({
    ledger => $self->ledger,
  });
}

test "accessor" => sub {
  my ($self) = @_;

  my $r = $self->refund();

  my @refunds = $self->ledger->refunds();
  is(@refunds, 0, "before list");
  is_deeply(\@refunds, $self->ledger->refund_array, "before array");
  $self->ledger->add_refund($r);
  @refunds = $self->ledger->refunds();
  is(@refunds, 1, "after list");
  is_deeply(\@refunds, $self->ledger->refund_array, "after array");
};

test "constructor" => sub {
  my ($self) = @_;
  my $c = $self->ledger->refund_collection;
  ok($c->does("Moonpig::Role::CollectionType"));
};

sub refund_amounts {
  join ", " => sort map $_->amount, @_;
}

test "collection object" => sub {
  my ($self) = @_;
  my $credit = $self->ledger->add_credit(
    class('Credit::Simulated', 't::Refundable::Test'),
    { amount => dollars(5_000) },
  );

  my $c = $self->ledger->refund_collection();
  ok($c);
  ok($c->does("Moonpig::Role::CollectionType"));

  my @r;

  for (0..2) {
    $c = $self->ledger->refund_collection();
    is($c->count, @r, "collection contains $_ refund(s)" );
    is(refund_amounts($c->all), refund_amounts(@r), "amounts are correct");
    last if $_ == 2;
    push @r, my $next_refund = $self->ledger->add_refund(class('Refund'));
    $self->ledger->create_transfer({
      type => 'credit_application',
      from => $credit,
      to => $next_refund,
      amount => dollars(10) + $_ * dollars(1.01),
    });
  }

  note "0..2 done, starting 3..5\n";

  for (3..5) {
    $c = $self->ledger->refund_collection();
    is($c->count, @r, "collection contains $_ refund(s)" );
    is(refund_amounts($c->all), refund_amounts(@r), "amounts are correct");
    last if $_ == 5;
    push @r, my $next_refund = class('Refund')->new({ledger => $self->ledger});
    $c->add({ new_item => $next_refund });
    $self->ledger->create_transfer({
      type => 'credit_application',
      from => $credit,
      to => $next_refund,
      amount => dollars(10) + $_ * dollars(1.01),
    });
  }
};

test "ledger gc" => sub {
  my ($self) = @_;
  my $rc = $self->ledger->refund_collection();
  $self->scrub_ledger;
  ok($rc->owner, "was ledger prematurely garbage-collected?");
};

run_me;
done_testing;

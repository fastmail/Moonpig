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
  isa => 'Moonpig::Class::Ledger',
  lazy => 1,
  default => sub { $_[0]->test_ledger },
  clearer => 'scrub_ledger',
);

before run_test => sub {
  my ($self) = @_;

  $self->scrub_ledger;
};

test "accessor" => sub {
  my ($self) = @_;
  my $r = class("Refund")->new({
    ledger => $self->ledger,
    amount => dollars(1)
  });

  my @refunds = $self->ledger->refunds();
  is(@refunds, 0, "before list");
  is_deeply(\@refunds, $self->ledger->refund_array, "before array");
  $self->ledger->add_refund($r);
  @refunds = $self->ledger->refunds();
  is(@refunds, 1, "after list");
  is_deeply(\@refunds, $self->ledger->refund_array, "after array");
};

test "constructor" => sub {
  ok(1);
};


run_me;
done_testing;

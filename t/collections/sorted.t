#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Test::Fatal;
use Test::Routine;
use Test::Routine::Util -all;
use t::lib::TestEnv;
use Moonpig::Util qw(class cents dollars);

use Moonpig::Test::Factory qw(build_ledger);

my ($Ledger, $Credit);

before run_test => sub {
  my ($self) = @_;

  $Ledger = build_ledger();
  $Credit = $Ledger->add_credit(
    class('Credit::Simulated', 't::Refundable::Test'),
    { amount => dollars(5_000) },
  );
};

sub refund {
  my ($self, $amount) = @_;
  my $refund = $Ledger->add_debit(class('Debit::Refund'));
  $amount ||= dollars(1);
  $Ledger->create_transfer({
    type => 'debit',
    from => $Credit,
    to   => $refund,
    amount => $amount,
  });
  return $refund;
}

test "refund collections" => sub {
  my ($self) = @_;

  my @r;
  for (4, 2, 8, 5, 7, 1) {
    $self->refund(cents($_ * 101));
  }

  my @refunds = $Ledger->debits();
  is(@refunds, 6, "ledger loaded with five refunds");
  my $rc = $Ledger->debit_collection;

  is( exception { $rc->sort_key("amount") },
      undef,
      "set sort method name to 'amount'" );

  { my @all = $rc->all_sorted;
    is_deeply([ map $_->amount, @all ],
              [ map dollars($_), 1.01, 2.02, 4.04, 5.05, 7.07, 8.08 ],
              '->all_sorted');
  }

  is($rc->first->amount, dollars(1.01), "->first is least");
  is($rc->last ->amount, dollars(8.08), "->last is most");
};

test "miscellaneous tests" => sub {
  my ($self) = @_;
  my $cc = $Ledger->consumer_collection;

  like( exception { $cc->all_sorted },
        qr/\ACan't locate object method "all_sorted"/i,
        "consumer collection does not implement sorting" );

 # Can't get TODO working with Test::Routine
 TODO: {
     local $TODO = "Can't check sort key method name without method_name_for type";
#     isnt( exception { $cc->sort_key("uglification") },
#           undef,
#           "correctly failed to set sort method name to something bogus" );
  }
};

run_me;
done_testing;

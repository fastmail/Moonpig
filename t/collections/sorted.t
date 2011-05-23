#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Test::Fatal;
use Test::Routine;
use Test::Routine::Util -all;
use Moonpig::Env::Test;
use Moonpig::Util qw(class cents dollars);

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

has credit => (
  is => 'rw',
  does => 'Moonpig::Role::Credit',
  clearer => 'scrub_credit',
);

before run_test => sub {
  my ($self) = @_;

  $self->scrub_ledger;
  my $credit = $self->ledger->add_credit(
    class('Credit::Simulated', 't::Refundable::Test'),
    { amount => dollars(5_000) },
  );
  $self->credit($credit);
};

sub refund {
  my ($self, $amount) = @_;
  my $refund = $self->ledger->add_refund(class('Refund'));
  $amount ||= dollars(1);
  $self->ledger->create_transfer({
    type => 'credit_application',
    from => $self->credit,
    to => $refund,
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

  my @refunds = $self->ledger->refunds();
  is(@refunds, 6, "ledger loaded with five refunds");
  my $rc = $self->ledger->refund_collection;

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
  my $cc = $self->ledger->consumer_collection;

  like( exception { $cc->all_sorted },
        qr/no sort key defined/i,
        "no default sort key for consumers" );

 # Can't get TODO working with Tsst::Routine
 TODO: {
     local $TODO = "Can't check sort key method name without method_name_for type";
#     isnt( exception { $cc->sort_key("uglification") },
#           undef,
#           "correctly failed to set sort method name to something bogus" );
  }
};

run_me;
done_testing;

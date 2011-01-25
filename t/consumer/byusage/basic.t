use strict;
use warnings;

use Carp qw(confess croak);
use Moonpig::Util -all;
use Test::Routine;
use Test::More;
use Test::Routine::Util;

has ledger => (
  is   => 'rw',
  does => 'Moonpig::Role::Ledger',
  default => sub { $_[0]->test_ledger() },
  lazy => 1,
  clearer => 'scrub_ledger',
);
sub ledger;  # Work around bug in Moose 'requires';

has consumer => (
  is   => 'rw',
  does => 'Moonpig::Role::Consumer::ByUsage',
  default => sub { $_[0]->test_consumer('ByUsage') },
  lazy => 1,
  clearer => 'discard_consumer',
  predicate => 'has_consumer',
);

has hold => (
  is   => 'rw',
  isa => 'Moonpig::Hold',
  clearer => 'discard_hold',
);

with(
  't::lib::Factory::Consumers',
  't::lib::Factory::Ledger',
);

use t::lib::Logger;

before run_test => sub {
  my ($self) = @_;
  $self->discard_consumer;
  $self->discard_hold;
  Moonpig->env->email_sender->clear_deliveries;
};

test create_consumer => sub {
  my ($self) = @_;
  return if $self->has_consumer;

  my $b = class('Bank')->new({
    ledger => $self->ledger,
    amount => dollars(1),
  });

  $self->consumer(
    $self->test_consumer(
      'ByUsage',
      { bank => $b,
        ledger => $self->ledger,
      }));
  ok($self->consumer, "set up consumer");
  ok($self->consumer->does('Moonpig::Role::Consumer::ByUsage'),
     "consumer is correct type");
  is($self->consumer->bank, $b, "consumer has bank");
  is($self->consumer->unapplied_amount, dollars(1), "bank contains \$1");
};

test successful_hold => sub {
  my ($self) = @_;
  $self->create_consumer;
  is($self->consumer->units_remaining, 20, "initially funds for 20 units");
  my $h = $self->consumer->create_hold_for_units(7);
  ok($h, "made hold");
  $self->hold($h);
  is($h->consumer, $self->consumer, "hold has correct consumer");
  is($h->bank, $self->consumer->bank, "hold has correct bank");
  is($h->amount, cents(35), "hold is for \$.35");
  is($self->consumer->units_remaining, 13, "after holding 7, there are 13 left");
};

test release_hold => sub {
  my ($self) = @_;
  $self->scrub_ledger;
  $self->successful_hold;
  is($self->consumer->units_remaining, 13, "still 13 left in bank");
  $self->hold->delete;
  is($self->consumer->units_remaining, 20, "20 left after releasing hold");
};

test commit_hold => sub {
  my ($self) = @_;
  my @journals;
  $self->successful_hold;
  @journals = $self->ledger->journals;
  is(@journals, 0, "no journal yet");
  note("creating charge for hold");
  $self->consumer->create_charge_for_hold($self->hold, "test charge");
  is($self->consumer->units_remaining, 13, "still 13 left in bank");
  @journals = $self->ledger->journals;
  is(@journals, 1, "now one journal");
  is($journals[0]->charge_tree->total_amount, cents(35),
     "total charges now \$.35");
};

test failed_hold => sub {
  ok(1);
};

test create_replacement => sub {
  ok(1);
};

test low_water_check => sub {
  ok(1);
};

test usage_estimate => sub {
  ok(1);
};

test expiration => sub {
  ok(1);
};

run_me;
done_testing;

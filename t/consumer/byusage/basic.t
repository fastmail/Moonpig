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
);
sub ledger;  # Work around bug in Moose 'requires';

has consumer => (
  is   => 'rw',
  does => 'Moonpig::Role::Consumer::ByUsage',
  default => sub { $_[0]->test_consumer('ByUsage') },
  lazy => 1,
  clearer => 'discard_consumer',
);

with(
  't::lib::Factory::Consumers',
  't::lib::Factory::Ledger',
);

use t::lib::Logger;

before run_test => sub {
  Moonpig->env->email_sender->clear_deliveries;
};

test create_consumer => sub {
  my ($self) = @_;
  $self->consumer($self->test_consumer('ByUsage'));
  ok($self->consumer);
  ok($self->consumer->does('Moonpig::Role::Consumer::ByUsage'));
};

test successful_hold => sub {
  ok(1);
};

test commit_hold => sub {
  ok(1);
};

test rollback_hold => sub {
  ok(1);
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


use strict;
use Moonpig::Util qw(class days dollars);
use Test::More;
use Test::Routine;
use Test::Routine::Util;

with qw(t::lib::Factory::Ledger
        t::lib::Role::UsesStorage);

my ($ledger_a, $ledger_b, $A, $B);

before run_test => sub {
  my ($self) = @_;
  $_ = $self->test_ledger(class('Ledger'),
                          { contact => $self->random_contact })
    for $ledger_a, $ledger_b;
  $A = $ledger_a->guid;
  $B = $ledger_b->guid;
  die if $A eq $B;
};

test dummy => sub {
  my ($self) = @_;
  my $consumer = $self->add_consumer_to($ledger_a);
  my $copy = $consumer->copy_to($ledger_b);
  isnt($consumer, $copy, "copied, not moved");
  is($copy->ledger, $ledger_b, "copy is in ledger b");
  ok($copy->is_active, "copy is active");
  ok(! $consumer->is_active, "original is no longer active");
  is($ledger_b->active_consumer_for_xid($consumer->xid),
     $copy,
     "new ledger found active copy with correct xid");
  is($ledger_a->active_consumer_for_xid($consumer->xid),
     undef,
     "old ledger no longer finds consumer for this xid");
  is($copy->replacement_mri, $consumer->replacement_mri,
     "same replacement_mri");
};

test bytime => sub {
  ok(1);
};

test with_bank => sub {
  ok(1);
};

test with_replacement => sub {
  ok(1);
};


run_me;
done_testing;

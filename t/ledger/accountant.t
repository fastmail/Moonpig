
use strict;
use warnings;

use Carp qw(confess croak);
use Moonpig::Util -all;
use Test::Routine;
use Test::More;
use Test::Routine::Util;
with ('t::lib::Factory::Ledger');

has ledger => (
  is   => 'rw',
  does => 'Moonpig::Role::Ledger',
  default => sub { $_[0]->test_ledger() },
  lazy => 1,
  clearer => 'scrub_ledger',
  handles => [ qw(accountant) ],
);

test basic => sub {
  my ($self) = @_;
  ok($self->ledger->accountant, "default ledger has accountant");
  isa_ok($self->accountant, "Moonpig::Ledger::Accountant",
         "It is in the right class");
};

test typemap => sub {
  my ($self) = @_;
  my $ac = $self->accountant;
  ok(  $ac->type_is_ok('bank', 'consumer', 'transfer'));
  ok(! $ac->type_is_ok('consumer', 'bank', 'transfer'));
  ok(! $ac->type_is_ok('consumer', 'bank', 'potato'));
  ok(! $ac->type_is_ok('consumer', 'bank', 'hold'));
  ok(  $ac->type_is_ok('bank', 'credit', 'bank_credit'));
  ok(! $ac->type_is_ok('potato', 'credit', 'bank_credit'));
  ok(! $ac->type_is_ok('potato', 'potato', 'bank_credit'));
};



run_me;
done_testing;

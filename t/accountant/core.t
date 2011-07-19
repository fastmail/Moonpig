
use strict;
use warnings;

use Carp qw(confess croak);
use Moonpig::Util -all;
use Test::Routine;
use Test::More;
use Test::Routine::Util;
with ('t::lib::Factory::Ledger');

use Moonpig::Context::Test -all, '$Context';

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

run_me;
done_testing;

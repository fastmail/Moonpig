use strict;
use warnings;

use Carp qw(confess croak);
use Moonpig::TransferUtil ':all';
use Moonpig::Util qw(class);
use Test::Routine;
use Test::More;
use Test::Routine::Util;

test "legal transfer mapping" => sub {
  ok(  transfer_type_ok('bank', 'consumer', 'transfer'));
  ok(! transfer_type_ok('consumer', 'bank', 'transfer'));
  ok(! transfer_type_ok('consumer', 'bank', 'potato'));
  ok(! transfer_type_ok('consumer', 'bank', 'hold'));
  ok(  transfer_type_ok('bank', 'credit', 'bank_credit'));
  ok(! transfer_type_ok('potato', 'credit', 'bank_credit'));
  ok(! transfer_type_ok('potato', 'potato', 'bank_credit'));
};

test "valid transfer types" => sub {
  ok(  valid_type('transfer'));
  ok(  valid_type('bank_credit'));
  ok(! valid_type('potato'));
};

test "deletable transfer types" => sub {
  ok(  deletable('hold'));
  ok(! deletable('transfer'));
};

test "transfer-capable entities" => sub {
  ok(  is_transfer_capable('bank'));
  ok(  is_transfer_capable('consumer'));
  ok(! is_transfer_capable('potato'));
};

test transferer_type => sub {
  is(class('Bank')->transferer_type, 'bank');
  is(class('Consumer::Dummy')->transferer_type, 'consumer');
};

run_me;
done_testing;

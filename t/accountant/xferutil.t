use strict;
use warnings;

use Carp qw(confess croak);
use Moonpig::TransferUtil ':all';
use Moonpig::Util qw(class);
use Test::Routine;
use Test::More;
use Test::Routine::Util;

test "legal transfer mapping" => sub {
  ok(  transfer_type_ok('consumer', 'journal',  'transfer'));
  ok(! transfer_type_ok('journal',  'consumer', 'transfer'));
  ok(! transfer_type_ok('consumer', 'journal',  'potato'));
  ok(! transfer_type_ok('journal',  'consumer', 'hold'));
  ok(  transfer_type_ok('consumer', 'credit',   'cashout'));
  ok(! transfer_type_ok('potato',   'credit',   'cashout'));
  ok(! transfer_type_ok('potato',   'potato',   'cashout'));
};

test "valid transfer types" => sub {
  ok(  valid_type('transfer'));
  ok(  valid_type('cashout'));
  ok(! valid_type('potato'));
};

test "deletable transfer types" => sub {
  ok(  deletable('hold'));
  ok(! deletable('transfer'));
};

test "transfer-capable entities" => sub {
  ok(  is_transfer_capable('journal'));
  ok(  is_transfer_capable('consumer'));
  ok(! is_transfer_capable('potato'));
};

test transferer_type => sub {
  is(class('Journal')->transferer_type, 'journal');
  is(class('Consumer::Dummy')->transferer_type, 'consumer');
};

run_me;
done_testing;

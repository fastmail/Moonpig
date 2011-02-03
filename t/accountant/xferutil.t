use strict;
use warnings;

use Carp qw(confess croak);
use Moonpig::TransferUtil;
use Moonpig::Util qw(class);
use Test::Routine;
use Test::More;
use Test::Routine::Util;

test typemap => sub {
  ok(  Moonpig::TransferUtil->transfer_type_ok('bank', 'consumer', 'transfer'));
  ok(! Moonpig::TransferUtil->transfer_type_ok('consumer', 'bank', 'transfer'));
  ok(! Moonpig::TransferUtil->transfer_type_ok('consumer', 'bank', 'potato'));
  ok(! Moonpig::TransferUtil->transfer_type_ok('consumer', 'bank', 'hold'));
  ok(  Moonpig::TransferUtil->transfer_type_ok('bank', 'credit', 'bank_credit'));
  ok(! Moonpig::TransferUtil->transfer_type_ok('potato', 'credit', 'bank_credit'));
  ok(! Moonpig::TransferUtil->transfer_type_ok('potato', 'potato', 'bank_credit'));
};

test type => sub {
  ok(  Moonpig::TransferUtil->valid_type('transfer'));
  ok(  Moonpig::TransferUtil->valid_type('bank_credit'));
  ok(! Moonpig::TransferUtil->valid_type('potato'));
};

test deletable => sub {
  ok(  Moonpig::TransferUtil->deletable('hold'));
  ok(! Moonpig::TransferUtil->deletable('transfer'));
};

test is_transfer_capable => sub {
  ok(  Moonpig::TransferUtil->is_transfer_capable('bank'));
  ok(  Moonpig::TransferUtil->is_transfer_capable('consumer'));
  ok(! Moonpig::TransferUtil->is_transfer_capable('potato'));
};

test transferer_type => sub {
  is(class('Bank')->transferer_type, 'bank');
  is(class('Consumer::Dummy')->transferer_type, 'consumer');
};

run_me;
done_testing;

use strict;
use warnings;

use Carp qw(confess croak);
use Moonpig::TransferUtil;
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

run_me;
done_testing;

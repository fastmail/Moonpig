use strict;
use warnings;

use Carp qw(confess croak);
use Test::More;
use Test::Routine;
use Test::Routine::Util;

test null => sub {
  ok(1);
};

run_me;
done_testing;

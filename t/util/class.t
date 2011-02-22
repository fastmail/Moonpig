use strict;
use warnings;

use Test::More;

use Moonpig::Util qw(class);

subtest "memoization" => sub {
  plan tests => 3;
  my @class;
  push @class, class('Refund') for 1..2;
  push @class, scalar(class('Refund')) for 1..2;
  for (1..3) {
    is($class[0], $class[$_]);
  }
};

done_testing;

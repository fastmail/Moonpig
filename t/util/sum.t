use strict;
use warnings;

use Test::More;

use Moonpig::Util qw(sum);

is(sum(), 0, "empty sum");
isnt(sum(), undef, "empty sum");
isnt(sum(), "", "empty sum");
is(sum(1..10), 55, "nonempty sum");

done_testing;

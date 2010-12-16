use strict;
use warnings;

use Test::More;

use Moonpig::Types qw(CostPath Millicents);

{
  my $val = 1.12;
  my $amt = Millicents->assert_coerce($val);
  is("$amt", "1", "we truncate away fractional amounts");
}

is_deeply(
  CostPath->assert_coerce('foo.bar.baz'),
  [ qw(foo bar baz) ],
  "can convert dotted-string to cost path array",
);

is_deeply(
  CostPath->assert_coerce(''),
  [ ],
  "can convert empty-tring to (empty) cost path array",
);

done_testing;

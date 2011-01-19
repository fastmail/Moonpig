use strict;
use warnings;

use Test::More;

use Moonpig::Types qw(ChargePath Millicents);

{
  my $val = 1.12;
  my $amt = Millicents->assert_coerce($val);
  is("$amt", "1", "we truncate away fractional amounts");
}

is_deeply(
  ChargePath->assert_coerce('foo.bar.baz'),
  [ qw(foo bar baz) ],
  "can convert dotted-string to cost path array",
);

is_deeply(
  ChargePath->assert_coerce(''),
  [ ],
  "can convert empty-tring to (empty) cost path array",
);

done_testing;

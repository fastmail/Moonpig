use strict;
use warnings;

use Test::More;

use Moonpig::Types qw(CostPath Millicents);
use Moonpig::Util qw(assert_to);

{
  my $val = 1.12;
  my $amt = assert_to(Millicents => $val);
  is("$amt", "1", "we truncate away fractional amounts");
}

is_deeply(
  assert_to(CostPath => 'foo.bar.baz'),
  [ qw(foo bar baz) ],
  "can convert dotted-string to cost path array",
);

is_deeply(
  assert_to( CostPath => '' ),
  [ ],
  "can convert empty-tring to (empty) cost path array",
);

done_testing;

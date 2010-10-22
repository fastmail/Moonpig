use strict;
use warnings;

use Test::More;

use Moonpig::Types qw(CostPath);

my $path_str = 'foo.bar.baz';
my $path     = to_CostPath($path_str);

is_deeply(
  $path,
  [ qw(foo bar baz) ],
  "can convert dotted-string to cost path array",
);

done_testing;

use strict;
use warnings;

use Test::More;

use Moonpig::Util qw(sum sumof);

is(sum(), 0, "empty sum");
isnt(sum(), undef, "empty sum");
isnt(sum(), "", "empty sum");
is(sum(1..10), 55, "nonempty sum");

{
  my $res = sumof { $_->[1] } [1,4], [2,8], [5,7];
  is ($res, 19, "sumof");

  my (@dig, @empty) = (1, 4, 2, 8, 5, 7);
  $res = sumof { 2 * $_ } @dig;
  is ($res, 54, "sumof");

  is ((sumof { 2 * $_ } @empty), 0, "empty sumof");
}


done_testing;

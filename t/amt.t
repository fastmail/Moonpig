use strict;
use warnings;
use Test::More;

use Moonpig::Types qw(Millicents);

{
  my $val = 1.12;
  my $amt = to_Millicents($val);
  is("$amt", "1", "we truncate away fractional amounts");
}

done_testing;

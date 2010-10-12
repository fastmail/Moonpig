use strict;
use warnings;
use Test::More;

use Moonpig::Types qw(MoneyAmount);

{
  my $val = 1.12;
  my $amt = to_MoneyAmount($val);
  is("$amt", "1.1200", "we can coerce dollars-and-cents to MoneyAmounts");
}

{
  my $val = 1.12345;
  my $amt = to_MoneyAmount($val);
  is("$amt", "1.1234", "we can coerce over-precise values to MoneyAmounts");
}

done_testing;

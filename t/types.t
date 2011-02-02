use strict;
use warnings;

use Test::More;

use Moonpig::Types qw(ChargePath Millicents Time);

use Scalar::Util qw(refaddr);

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

{
  my $datetime = DateTime->now;
  my $mp_dt    = Time->assert_coerce($datetime);

  isnt(
    refaddr($datetime),
    refaddr($mp_dt),
    "coerce DT -> M::DT gets a new object",
  );

  isa_ok($mp_dt, 'Moonpig::DateTime', 'coerce DT -> M::DT gets M::DT');
  cmp_ok($mp_dt, '==', $datetime, '...and the M::DT == the DT');
}

done_testing;

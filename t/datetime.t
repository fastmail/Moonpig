
use strict;
use warnings;

use Carp qw(confess croak);
use Moonpig::Util -all;
use Moonpig::DateTime;
use Test::Routine;
use Test::More;
use Test::Routine::Util;

sub jan {
  my ($day) = @_;
  Moonpig::DateTime->new( year => 2000, month => 1, day => $day );
}

test compare => sub {
  my ($self) = @_;
  plan tests => 10;
  my ($j1, $j2) = (jan(1), jan(2));
  cmp_ok($j1, '==', $j1);
  cmp_ok($j1, '!=', $j2);
  ok(! $j1->precedes($j1));
  ok(  $j1->precedes($j2));
  ok(! $j2->precedes($j1));
  ok(! $j2->precedes($j2));
  ok(! $j1->follows($j1));
  ok(! $j1->follows($j2));
  ok(  $j2->follows($j1));
  ok(! $j2->follows($j2));
};

run_me;
done_testing;

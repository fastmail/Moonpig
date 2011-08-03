
package main;
use strict;
use warnings;

use Carp qw(confess croak);
use Data::GUID qw(guid_string);
use Moonpig::URI;
use Moonpig::Util qw(days dollars);
use Test::More;
use Try::Tiny;

use Moose;

my $day = days(1);
plan tests => 4;

is(Moonpig::URI->nothing->construct, undef, "nothing => undef");

for my $bad (qw(moonpig://foo
                moonpig://test/bar
                moonpig://test/consumer/ByTime/yobgorgle
              )) {
  my $mri = Moonpig::URI->new($bad) or die "Couldn't make '$bad'";
  try {
    $mri->construct;
  } finally {
    ok(@_, "$bad failed");
  }
}

done_testing;



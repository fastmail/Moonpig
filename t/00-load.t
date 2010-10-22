use strict;
use warnings;

use Test::More;

my @files = grep { /\.pm$/ } `find lib -type f`;

chomp @files;
s{^lib/}{}, s{\.pm$}{}, s{/}{::}g for @files;

my %failed = map { eval "require $_; 1" ? () : ($_ => $@) } @files;

if (keys %failed) {
  for my $key (keys %failed) {
    diag "Failed to load $key:";
    diag $failed{$key};
  }

  BAIL_OUT "compilation failures";
} else {
  pass("all libraries loaded");
}

done_testing;

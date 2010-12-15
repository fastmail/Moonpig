use strict;
use warnings;

use Test::More;

require_ok 'Moonpig' or BAIL_OUT "compilation failures";

my @files = grep { /\.pm$/ } `find lib -type f`;

chomp @files;
s{^lib/}{}, s{\.pm$}{}, s{/}{::}g for @files;

my %failed = map { eval "require $_; Moonpig->_scrub_env; 1" ? () : ($_ => $@) } @files;

if (keys %failed) {
  for my $key (keys %failed) {
    diag "Failed to load $key:";
    diag $failed{$key};
  }

  BAIL_OUT "compilation failures: @{[sort keys %failed]}";
} else {
  pass("all libraries loaded");
}

done_testing;

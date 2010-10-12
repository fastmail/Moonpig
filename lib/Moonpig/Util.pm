package Moonpig::Util;
use strict;
use warnings;

use Sub::Exporter -setup => [ qw(dollars) ];

sub dollars {
  my ($dollars) = @_;
  my $millicents = $dollars * 100 * 1000;

  return int $millicents;
}

1;

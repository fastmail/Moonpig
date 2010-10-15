package Moonpig::Util;
use strict;
use warnings;
use Carp qw(croak);
use Scalar::Util qw(refaddr);

use Sub::Exporter -setup => [ qw(dollars same_object) ];

sub dollars {
  my ($dollars) = @_;
  my $millicents = $dollars * 100 * 1000;

  return int $millicents;
}

sub same_object {
    my ($a, $b) = @_;
    my $me = "Moonpig::Util::same_object";
    @_ == 2 or croak(@_ . " arguments to $me");
    my ($ra, $rb) = (refaddr $a, refaddr $b);
    defined($ra) or croak("arg 1 to $me was not a reference");
    defined($rb) or croak("arg 2 to $me was not a reference");

    $ra == $rb;
}

1;

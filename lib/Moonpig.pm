use strict;
use warnings;
package Moonpig;
# ABSTRACT: a flexible billing system

use Config ();
use Carp ();

Carp::croak("Moonpig requires a perl compile with use64bitint")
  unless $Config::Config{use64bitint};

my $env;

sub set_env {
  my ($self, $new_env) = @_;
  Carp::croak("environment is already configured") if $env;
  $env = $new_env;
}

sub _scrub_env { undef $env }

sub env {
  Carp::croak("environment not yet configured") if ! $env;
  $env
}

1;

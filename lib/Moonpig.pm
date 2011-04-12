use strict;
use warnings;
package Moonpig;
# ABSTRACT: a flexible billing system

use Config ();
use Carp ();

Carp::croak("Moonpig requires a perl compile with use64bitint")
  unless $Config::Config{use64bitint} || $ENV{Moonpig32BitsOK};

my $env;

sub set_env {
  my ($self, $new_env) = @_;
  if ($env) {
    if (Scalar::Util::refaddr($new_env) == Scalar::Util::refaddr($env)) {
      return;
    } else {
      Carp::croak("environment is already configured");
    }
  }

  $env = $new_env;
}

sub _scrub_env { undef $env }

sub env {
  Carp::croak("environment not yet configured") if ! $env;
  $env
}

1;

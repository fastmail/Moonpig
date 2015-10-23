use strict;
use warnings;
package Moonpig;
# ABSTRACT: a flexible billing system

use Config ();
use Carp ();

# We used to say that you needed 64-bit perl to avoid roundoff errors, but we
# couldn't get a 64-bit perl working correctly on Solaris, so rather than hem
# and haw about roundoff errors at thousands and thousands of dollars, we're
# just going to cope with it.  Nobody pays us that much, anyway.
# -- rjbs, 2012-02-10
# Carp::croak("Moonpig requires a perl compile with use64bitint")
#   unless $Config::Config{use64bitint} || $ENV{Moonpig32BitsOK};

my $env;

{ no warnings 'once'; $Moonpig::Storage::LAST = []; }

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

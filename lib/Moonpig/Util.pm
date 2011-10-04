use strict;
use warnings;
package Moonpig::Util;
# ABSTRACT: essential extra helper functions for Moonpig

use Moonpig;
use Moonpig::Types ();
use Moonpig::Events::Event;

use Moose::Util::TypeConstraints ();

use Carp qw(croak);
use MooseX::ClassCompositor;
use MooseX::StrictConstructor::Trait::Class;
use Moose::Util::MetaRole ();
use Scalar::Util qw(refaddr);
use String::RewritePrefix;

use Sub::Exporter -setup => [ qw(
  class class_roles

  event

  cents dollars to_cents to_dollars

  days weeks months years

  same_object

  percent

  sum
) ];

my $COMPOSITOR = MooseX::ClassCompositor->new({
  class_basename  => 'Moonpig::Class',
  class_metaroles => {
    class => [
      'MooseX::StrictConstructor::Trait::Class',
      'Stick::Trait::Class::CanQueryPublished',
    ],
  },
  role_prefixes   => {
   ''    => 'Moonpig::Role::',
   '='   => '',
   't::' => 't::lib::Role::',
  }
});

use Moose::Util qw(apply_all_roles);
# Arguments here are role names, or role objects followed by nonce-names.

sub class {
  $COMPOSITOR->class_for(@_);
}

sub class_roles {
  return { $COMPOSITOR->known_classes };
}

sub event {
  my ($ident, $payload) = @_;

  $payload ||= {};
  $payload->{timestamp} ||= Moonpig->env->now();

  Moonpig::Events::Event->new({
    ident   => $ident,
    payload => $payload,
  });
}

sub cents {
  my ($cents) = @_;
  my $millicents = $cents * 1000;

  return int ($millicents + 0.5);
}

# returns unrounded fractional cents
# to_cents(142857) returns 142.857 cents
sub to_cents {
  my ($millicents) = @_;
  return $millicents / 1000;
}

sub dollars {
  my ($dollars) = @_;
  my $millicents = $dollars * 100 * 1000;

  return int ($millicents + 0.5);
}

# returns unrounded fractional dollars
# to_dollars(142857) returns 1.42857 dollars
sub to_dollars {
  my ($millicents) = @_;
  return $millicents / (1000 * 100);
}

sub days { $_[0] * 86400 } # Ignores leap seconds and DST
sub weeks { $_[0] * 86400 * 7 }
sub months { $_[0] * 86400 * 30 } # also ignores varying month lengths
sub years { $_[0] * 86400 * 365.25 } # also ignores the Gregorian calendar
                                     # Hail Caesar!

sub same_object {
  my ($a, $b) = @_;
  my $me = "Moonpig::Util::same_object";
  @_ == 2 or croak(@_ . " arguments to $me");
  my ($ra, $rb) = (refaddr $a, refaddr $b);
  defined($ra) or croak("arg 1 to $me was not a reference");
  defined($rb) or croak("arg 2 to $me was not a reference");

  $ra == $rb;
}

sub sum {
  require List::Util;
  return List::Util::reduce(sub { $a + $b }, 0, @_);
}

sub percent { $_[0] / 100 }

1;

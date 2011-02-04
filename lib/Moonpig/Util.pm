use strict;
use warnings;
package Moonpig::Util;
# ABSTRACT: essential extra helper functions for Moonpig

use Moonpig;
use Moonpig::Types ();
use Moonpig::Events::Event;

use Moose::Util::TypeConstraints ();

use Carp qw(croak);
use Memoize;
use Scalar::Util qw(refaddr);
use String::RewritePrefix;

use Sub::Exporter -setup => [ qw(
  class

  event

  cents dollars

  days weeks months years

  same_object
) ];

memoize(class => (NORMALIZER => sub { join $;, sort @_ }));

sub class {
  my ($main, @rest) = @_;

  my @name_bits = @rest;
  s/::/_/g for @name_bits;

  my $name = join q{::}, 'Moonpig::Class', $main, @name_bits;

  my @roles = String::RewritePrefix->rewrite(
    {
      ''    => 'Moonpig::Role::',
      't::' => 't::lib::Role::',
    },
    $main, @rest,
  );

  my $class = Moose::Meta::Class->create( $name => (
    superclasses => [ 'Moose::Object' ],
    roles        => \@roles,
  ));

  $class->make_immutable;

  return $class->name;
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

sub dollars {
  my ($dollars) = @_;
  my $millicents = $dollars * 100 * 1000;

  return int ($millicents + 0.5);
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

1;

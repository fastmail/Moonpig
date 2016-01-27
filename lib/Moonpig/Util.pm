use 5.14.0;
use warnings;
package Moonpig::Util;
# ABSTRACT: essential extra helper functions for Moonpig

use Moonpig;
use Moonpig::Types ();
use Moonpig::Events::Event;

use Moose::Util::TypeConstraints ();

use Carp qw(croak);
use JSON 2;
use MooseX::ClassCompositor;
use MooseX::StrictConstructor::Trait::Class;
use Moose::Util::MetaRole ();
use Number::Nary ();
use Scalar::Util qw(refaddr);
use String::RewritePrefix;

use Sub::Exporter -setup => [ qw(
  class class_roles

  event

  cents dollars to_cents to_dollars

  datetime
  days weeks months years
  days_in_year

  json

  random_short_ident

  same_object

  pair_lefts pair_rights

  percent

  sum sumof
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

sub __round {
  my ($x) = @_;
  # The intention is to round halves towards infinity
  int( $x + ($x >= 0 ? .5 : -.5));
}

sub cents {
  my ($cents) = @_;
  __round($cents * 1000);
}

# returns unrounded fractional cents
# to_cents(142857) returns 142.857 cents
sub to_cents {
  my ($millicents) = @_;
  return $millicents / 1000;
}

sub dollars {
  my ($dollars) = @_;
  __round($dollars * 100 * 1000);
}

# returns unrounded fractional dollars
# to_dollars(142857) returns 1.42857 dollars
sub to_dollars {
  my ($millicents) = @_;
  return $millicents / (1000 * 100);
}

my %MONTH = (
  jan => 1, feb => 2, mar => 3, apr => 4, may => 5, jun => 6,
  jul => 7, aug => 8, sep => 9, oct =>10, nov =>11, dec =>12,
);

sub datetime {
  my ($m, $d, $y, $H, $M, $S) = @_;
  Carp::croak("no month given!") unless $m;
  $m = $MONTH{$m} // Carp::croak("don't understand month <$m>")
    unless $m =~ /\A[0-9]+\z/;
  Moonpig::DateTime->new(
    year   => $y // 2000,
    month  => $m,
    day    => $d // 1,
    hour   => $H // 0,
    minute => $M // 0,
    second => $S // 0,
  );
}

sub days { $_[0] * 86400 } # Ignores leap seconds and DST
sub weeks { $_[0] * 86400 * 7 }
sub months { $_[0] * 86400 * 30 } # also ignores varying month lengths
sub years { $_[0] * 86400 * 365.25 } # also ignores the Gregorian calendar
                                     # Hail Caesar!

sub days_in_year {
  my ($y) = @_;
  croak "4-digit year required" if $y < 1000;
  $y % 400 == 0 ? 366 :
  $y % 100 == 0 ? 365 :
  $y %   4 == 0 ? 366 : 365;
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

my ($_ENC) = Number::Nary::n_codec([ 2 .. 9, 'A', 'C' .. 'R', 'T' .. 'Z' ]);
sub random_short_ident {
  my ($size) = shift // 1e9;
  return $_ENC->( int rand $size );
}

sub pair_lefts {
  my (@pairs) = @_;
  map { $pairs[$_] } grep { $_ % 2 == 0 } keys @pairs;
}

sub pair_rights {
  my (@pairs) = @_;
  map { $pairs[$_] } grep { $_ % 2 == 1 } keys @pairs;
}

sub sum {
  require List::Util;
  return List::Util::reduce(sub { $a + $b }, 0, @_);
}

sub sumof (&@) {
  my ($f, @list) = @_;
  sum(map $f->($_), @list);
}

sub percent { $_[0] / 100 }

sub json {
  state $JSON = JSON->new->ascii(1)->convert_blessed(1)->allow_blessed;
  return $JSON;
}

1;

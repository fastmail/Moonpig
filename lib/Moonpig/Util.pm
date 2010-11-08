package Moonpig::Util;
use strict;
use warnings;
use Carp qw(croak);
use Scalar::Util qw(refaddr);

use Moonpig::Types ();
use Moonpig::Events::Event;

use Moose::Util::TypeConstraints ();

use Sub::Exporter -setup => [ qw(
  assert_to

  event

  cents dollars

  days weeks months years

  same_object
) ];

sub dollars {
  my ($dollars) = @_;
  my $millicents = $dollars * 100 * 1000;

  return int ($millicents + 0.5);
}

sub cents {
  my ($cents) = @_;
  my $millicents = $cents * 1000;

  return int ($millicents + 0.5);
}

sub days { $_[0] * 86400 } # Ignores leap seconds and DST
sub weeks { $_[0] * 86400 * 7 }
sub months { $_[0] * 86400 * 30 } # also ignores varying month lengths
sub years { $_[0] * 86400 * 365.25 } # also ignores the Gregorian calendar

sub event {
  my ($ident, $payload) = @_;
  Moonpig::Events::Event->new({
    ident   => $ident,
    (@_ > 1 ? (payload => $payload) : ()),
  });
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

# I really don't want to put this here, but I also really do not like the
# MooseX::Types to_Foo behavior of returning false on failure.  Until we get an
# assertive to, I will use this.
sub assert_to {
  my ($type, $value) = @_;
  my $tc = Moose::Util::TypeConstraints::find_type_constraint(
    'Moonpig::Types::' . $type
  );
  my $new_value = $tc->coerce($value);

  $tc->assert_valid($new_value);
  return $new_value;
}

1;

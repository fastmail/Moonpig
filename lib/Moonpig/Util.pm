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
  class class_roles

  event

  cents dollars

  days weeks months years

  same_object
) ];

 memoize(class => (NORMALIZER =>
                     sub { my @items = map ref() ? $_->[1] : $_, @_;
                           my $k = join $; => @items;
                           return $k;
                         },
                   LIST_CACHE => 'MERGE',
                  ));

use Moose::Util qw(apply_all_roles);
my $nonce = "00";
# Arguments here are role names, or role objects followed by nonce-names.

my %CLASS_ROLES;

sub class {
  my (@args) = @_;
  my @orig_args = @args;

  # $role_hash is a hash mapping nonce-names to role objects
  # $role_names is an array of names of more roles to add
  my (@roles, @role_class_names, @all_names);

  while (@args) {
    my $name = shift @args;
    if (ref $name) {
      my ($role_name, $moniker, $params) = @$name;

      my $full_name = _rewrite_prefix($role_name);
      Class::MOP::load_class($full_name);
      my $role_object = $full_name->meta->generate_role(
        parameters => $params,
      );

      push @roles, $role_object;
      $name = $moniker;
    } else {
      push @role_class_names, $name;
    }

    $name =~ s/::/_/g if @all_names;
    $name =~ s/^=//;

    push @all_names, $name;
  }

  my $name = join q{::}, 'Moonpig::Class', @all_names;

  @role_class_names = _rewrite_prefix(@role_class_names);

  Class::MOP::load_class($_) for @role_class_names;

  my $class = Moose::Meta::Class->create( $name => (
    superclasses => [ 'Moose::Object' ],
  ));
#  apply_all_roles($class, @role_class_names, @roles);
  apply_all_roles($class, @role_class_names, map $_->name, @roles);

  $class->make_immutable;

  $CLASS_ROLES{ $name } = \@orig_args;

  return $class->name;
}

sub _rewrite_prefix {
  my (@in) = @_;
  return String::RewritePrefix->rewrite(
    {
     ''    => 'Moonpig::Role::',
     '='   => '',
     't::' => 't::lib::Role::',
    },
    @in
  );
}

sub class_roles {
  return \%CLASS_ROLES;
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

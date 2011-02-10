use strict;
use warnings;
package Moonpig::URI;
# ABSTRACT: a URI used inside of Moonpig

use URI::Escape;
use Carp qw(confess croak);
use Scalar::Util 'reftype';

sub new {
  my $class = shift;
#  my $self = $class->SUPER::new(@_);
  my $arg = shift || return $class->nothing;
  my ($path, $query) = "$arg" =~
    m{\A moonpig://
      ([^?]*)           # path part
      (?: \? (.*) )?    # optional query part
   }xs
     or croak "Malformed MRI '$arg'";

  my @components = split m{/}, $path;

  bless {
    c => \@components,
    p => $class->parse_query_string($query) || {},
  } => $class;
}

sub as_string {
  my ($self) = @_;
  my $s = "moonpig://" . $self->path;
  my $qs = $self->query_string;
  defined($qs) and $s .= "?$qs";
  return $s;
}

sub path {
  my ($self) = @_;
  join "/", @{$self->{c}};
}

sub path_segments {
  my ($self) = @_;
  return wantarray ? @{$self->{c}} : $self->path;
}

sub params {
  my ($self) = @_;
  return wantarray ? %{$self->param_hash} : $self->param_hash;
}

sub param_hash { my %h = %{$_[0]{p}}; \%h }

sub query_string {
  my ($self) = @_;
  my %p = $self->params;
  my @kvp;
  while (my($k, $v) = each %p) {
    if (defined $v) {
      push @kvp, join "=", uri_escape($k), uri_escape($v);
    } else {
      unshift @kvp, uri_escape($k);
    }
  }
  return join "&", @kvp;
}

sub parse_query_string {
  my ($self, $s) = @_;
  my %h;
  return if ! defined($s) || $s eq "";

  for my $pair (split /&/, $s) {
    if ($pair =~ /(.*)=(.*)/) {
      $h{ uri_unescape($1) } = uri_unescape($2);
    } else {
      $h{ uri_unescape($pair) } = undef;
    }
  }
  return wantarray ? %h : \%h;
}

sub nothing { $_[0]->new("moonpig://nothing") }

my %TABLE = (
  nothing => sub { undef },

  'consumer-template' => sub {
    my ($path, $params, $extra) = @_;

    my $name = $path->[0];
    return Moonpig->env->consumer_template($name);
  },

  method => sub {
    my ($path, $params, $extra) = @_;
    my $self = delete $extra->{self}
      or confess "Missing 'self' argument in moonpig://test/method";
    my $meth = delete $params->{method}
      or confess "Missing 'method' argument in moonpig://test/method";
    return $self->$meth($params);
  }
);

# Replace this with some sort of more interesting and less centralized
# dispatcher later on
sub construct {
  my ($self, $args) = @_;
  $args ||= { };

  my (@path) = $self->path_segments;

  my $first   = shift @path;

  my $handler = $TABLE{ $first }
    or croak "Unknown Moonpig URI type <$first> in MRI $self";

  $handler->(\@path, $self->param_hash, $args->{extra} || {});
}

1;

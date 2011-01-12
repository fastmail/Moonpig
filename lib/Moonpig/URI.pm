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

my %table = (
  nothing => sub { undef },
  test => {
    callback => sub {
      my ($params, $extra) = @_;
      my $code = delete $extra->{code}
        or confess "Missing 'code' argument in moonpig://test/callback";
      return $code->($params);
    },
    consumer => {
      ByTime => sub {
        my ($params, $extra) = @_;
        require Moonpig::Util;
        return Moonpig::Util::class('Consumer::ByTime')->new({
          %$params,
          %$extra,
        })
      },
    },
    function => sub {
      my ($params, $extra) = @_;
      my $func = $params->{name}
        or confess "Missing 'name' argument in moonpig://test/function";
      no strict 'refs';
      return $func->($extra);
    },
    method => sub {
      my ($params, $extra) = @_;
      my $self = delete $extra->{self}
        or confess "Missing 'self' argument in moonpig://test/method";
      my $meth = delete $params->{method}
        or confess "Missing 'method' argument in moonpig://test/method";
      return $self->$meth($params);
    }
  },
);

# Replace this with some sort of more interesting and less centralized
# dispatcher later on
sub construct {
  my ($self, $args) = @_;
  $args ||= { };
  my $table = $args->{table} || \%table;
  my (@path) = $self->path_segments;
  while (my $c = shift @path) {
    croak "Unknown constructor path components <@path> in MRI $self"
      unless defined $table &&
        reftype($table) eq 'HASH' && exists $table->{$c};
    $table = $table->{$c};
  }

  if (reftype($table) eq 'HASH') {
    croak "Incomplete constructor path in MRI $self" unless defined $table;
  } elsif (reftype($table) eq 'CODE') {
    # A callback; call it using the query part of the URI as arguments
    return $table->($self->param_hash, $args->{extra} || {});
  } else {
    croak "Garbage value in MRI table for $self";
  }
}

1;

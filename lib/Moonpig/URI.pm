package Moonpig::URI;

use URI::Escape;
use Carp qw(confess croak);
use Scalar::Util 'reftype';
use strict;
use warnings;

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
  nothing => undef,
  test => {
    consumer => {
      ByTime => sub { Moonpig::Consumer::ByTime->new(@_) },
    }
  },
);

# Replace this with some sort of more interesting and less centralized
# dispatcher later on
sub construct {
  my ($self, $args, $table) = @_;
  $table ||= \%table;
  my (@path) = $self->path_segments;
  while (my $c = shift @path) {
    croak "Unknown constructor path components <@path> in MRI $self"
      unless defined $table &&
        reftype($table) eq 'HASH' && exists $table->{$c};
    $table = $table->{$c};
  }

  if (! defined $table) { return }
  elsif (reftype($table) eq 'HASH') {
    croak "Incomplete constructor path in MRI $self" unless defined $table;
  } else { return $table }      # not actually a table, but a result
}

1;

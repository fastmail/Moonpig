package Moonpig::URI;

use URI;
use Carp 'croak';
use Scalar::Util 'reftype';
use strict;
use warnings;

sub new {
  my $class = shift;
#  my $self = $class->SUPER::new(@_);
  my $arg = shift || return $class->nothing;
  my ($path) = "$arg" =~ m{\A moonpig:// (.*) }xs
    or croak "Malformed MRI '$arg'";
  my @components = split m{/}, $path;
  bless { c => \@components } => $class;
}

sub as_string {
  my ($self) = @_;
  "moonpig://" . $self->path;
}

sub path {
  my ($self) = @_;
  join "/", @{$self->{c}};
}

sub path_segments {
  my ($self) = @_;
  return wantarray ? @{$self->{c}} : $self->path;
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

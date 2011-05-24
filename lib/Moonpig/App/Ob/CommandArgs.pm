package Moonpig::App::Ob::CommandArgs;

{
  package Ob;
  use Moonpig::Util '-all';
  use Carp 'croak';
  # Special package for eval expression context
}

use Moose;
use Carp qw(confess croak);

has code => (
  is => 'ro',
  isa => 'CodeRef',
  required => 1,
);

has primary => (
  is => 'ro',
  isa => 'Str',
  required => 1,
);

has arg_list => (
  is => 'ro',
  isa => 'ArrayRef',
  default => sub { [] },
);

sub count {
  my ($self) = @_;
  return scalar @{$self->arg_list};
}

has orig => (
  is => 'ro',
  isa => 'Str',
  default => "",
);

sub orig_args {
  my ($self) = @_;
  my $args = $self->orig;
  my $prim = quotemeta($self->primary);
  $args =~ s/^\s*$prim//;
  return $args;
}

has hub => (
  is => 'ro',
  weak_ref => 1,
  required => 1,
);

sub run {
  my ($self) = @_;
  return $self->code->($self);
}

no Moose;

1;

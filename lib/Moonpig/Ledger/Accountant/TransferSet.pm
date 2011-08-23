use strict;
use warnings;

package Moonpig::Ledger::Accountant::TransferSet;
use Moonpig::TransferUtil ();

sub new {
  my ($class, $array) = @_;
  $array ||= [];

  bless [ @$array ] => $class;
}

sub filter {
  my ($self, $pred) = @_;
  bless [ grep $pred->($_), @$self ] => ref $self;
}

# return transfers newer than $max_age (which is in seconds)
sub newer_than {
  my ($self, $max_age) = @_;
  my $now = Moonpig->env->now();
  $self->filter(sub { $now - $_[0]->date < $max_age });
}

# return transfers older than $min_age (which is in seconds)
sub older_than {
  my ($self, $min_age) = @_;
  my $now = Moonpig->env->now();
  $self->filter(sub { $now - $_[0]->date > $min_age });
}

sub with_type {
  my ($self, $type) = @_;
  $self->filter(sub { $_[0]->type eq $type });
}

sub with_source {
  my ($self, $source) = @_;
  $self->filter(sub { $_[0]->source->guid eq $source->guid });
}

sub with_target {
  my ($self, $target) = @_;
  $self->filter(sub { $_[0]->target->guid eq $target->guid });
}

sub all {
  my ($self) = @_;
  return @$self;
}

sub total {
  my ($self) = @_;
  my $sum = 0;
  $sum += $_->amount for @$self;
  return $sum;
}

sub union {
  my ($class, @sets) = @_;
  my %e;
  $e{$_} = $_ for map @$_, @sets;
  bless [ values %e ] => $class;
}

sub _make_filter {
  my ($pred) = @_;
  sub { $_[0]->filter($pred) };
}

BEGIN {
  for my $type (Moonpig::TransferUtil::transfer_types) {
    no strict 'refs';
    *{"$type\_only"} = _make_filter(sub { $_[0]->type eq $type });
  }
}

1;

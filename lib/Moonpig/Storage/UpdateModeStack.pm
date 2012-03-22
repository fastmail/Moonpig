package Moonpig::Storage::UpdateModeStack;
use Moose;
# ABSTRACT: a stack of update modes for the storage engine

has stack => (
  is  => 'ro',
  isa => 'ArrayRef',
  default => sub { [] },
);

sub depth { scalar(@{$_[0]->stack}) }

sub is_nonempty {
  $_[0]->depth > 0;
}

sub is_empty {
  $_[0]->depth == 0;
}

sub get_top {
  if ($_[0]->is_nonempty) {
    return $_[0]->stack->[-1];
  } else {
    require Carp;
    Carp::confess "inspected top of empty update stack";
  }
}

sub pop_stack {
  my ($self) = @_;
  if ($self->is_nonempty) {
    pop @{$self->stack};
  } else {
    require Carp;
    Carp::confess "popped empty update stack";
  }
}

sub push {
  my ($self, $mode, $cb) = @_;
  push @{$self->stack}, $mode;
  return Moonpig::Storage::UpdateModeStack::StackPopper->new($self, $cb);
}

package Moonpig::Storage::UpdateModeStack::StackPopper;

sub new { my ($class, $stack, $cb) = @_; bless { stack => $stack, callback => $cb } => $class }

sub DESTROY {
  my ($popper) = @_;
  my $stack = $popper->{stack};
  $stack->pop_stack;
  $popper->{callback}->() if $stack->is_empty && $popper->{callback};
  return;
}

1;

package Moonpig::Storage::UpdateModeStack;

use Moose;

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
  push @{$_[0]->stack}, $_[1];
  return Moonpig::Storage::UpdateModeStack::StackPopper->new($_[0]);
}

package Moonpig::Storage::UpdateModeStack::StackPopper;

sub new { my ($class, $stack) = @_; bless { pop_me => $stack } => $class }
sub DESTROY { $_[0]{pop_me}->pop_stack }

1;

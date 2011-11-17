package Moonpig::Storage::UpdateModeStack;

use Moose;

has stack => (
  is  => 'ro',
  isa => 'ArrayRef',
  default => sub { [] },
);

sub is_nonempty {
  @{$_[0]->stack} > 0;
}

sub is_empty {
  @{$_[0]->stack} == 0;
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

sub push_false { $_[0]->push(0) }
sub push_true { $_[0]->push(1) }

package Moonpig::Storage::UpdateModeStack::StackPopper;

sub new { my ($class, $stack) = @_; bless { pop_me => $stack } => $class }
sub DESTROY { $_[0]{pop_me}->pop_stack }

1;

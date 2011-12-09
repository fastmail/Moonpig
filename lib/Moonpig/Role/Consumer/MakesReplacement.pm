package Moonpig::Role::Consumer::MakesReplacement;
# ABSTRACT: a consumer that makes a replacement for itself after a while
use Moose::Role;
use Moonpig::Types qw(TimeInterval);
use Moonpig::Util qw(event);

requires 'remaining_life';
requires 'will_die_soon';

# When the object has less than this long to live, it will
# create a replacement to invoice for the next service period
has old_age => (
  is => 'ro',
  isa => TimeInterval,
  traits => [ qw(Copy) ],
  predicate => 'has_old_age',
);

around will_die_soon => sub {
  my ($orig, $self, @args) = @_;
  if ($self->has_old_age) {
    return 1 if $self->remaining_life() < $self->old_age;
  }
  $self->$orig(@args);
};

sub maybe_make_replacement {
  my ($self) = @_;

  if ($self->needs_replacement) {
    $self->handle_event( event('consumer-create-replacement') );
  }
}

sub needs_replacement {
  my ($self) = @_;
  ! $self->has_replacement && $self->will_die_soon;
}

1;



package Moonpig::Role::Consumer::MakesReplacement;
# ABSTRACT: a consumer that makes a replacement for itself after a while
use Moose::Role;
use Moonpig::Logger '$Logger';
use Moonpig::Types qw(TimeInterval);
use Moonpig::Util qw(event);

requires 'remaining_life';
requires 'will_die_soon';

# When the object thinks its remaining life is less than or equal to this long,
# it will create a replacement to invoice for the next service period
#
# A consumer's replacement should be created no more than this much
# before the consumer expires.
has replacement_lead_time => (
  is => 'ro',
  isa => TimeInterval,
  traits => [ qw(Copy) ],
  predicate => 'has_replacement_lead_time',
);

around will_die_soon => sub {
  my ($orig, $self, @args) = @_;
  if ($self->has_replacement_lead_time) {
    return 1 if $self->remaining_life() <= $self->replacement_lead_time;
  }
  $self->$orig(@args);
};

sub maybe_make_replacement {
  my ($self) = @_;

  return unless $self->is_active;
  if ($self->needs_replacement) {
    $Logger->log([
      'creating replacement for consumer %s',
      $self->guid,
    ]);
    $self->handle_event( event('consumer-create-replacement') );
  }
}

sub needs_replacement {
  my ($self) = @_;
  ! $self->has_replacement && $self->will_die_soon;
}

1;

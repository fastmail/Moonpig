package Moonpig::Role::Consumer::ByUsage;
# ABSTRACT: a consumer that charges when told to

use Carp qw(confess croak);
use Moonpig;
use Moonpig::Events::Handler::Method;
use Moonpig::Trait::Copy;
use Moonpig::Util qw(class days event);
use Moose::Role;
use MooseX::Types::Moose qw(Num);

use Moonpig::Logger '$Logger';

with(
  'Moonpig::Role::Consumer',
  'Moonpig::Role::HandlesEvents',
  'Moonpig::Role::StubBuild',
  'Moonpig::Role::Consumer::MakesReplacement',
  'Moonpig::Role::Consumer::PredictsExpiration',
);

use Moonpig::Behavior::EventHandlers;
use Moonpig::Types qw(PositiveMillicents PositiveInt Time TimeInterval);

use namespace::autoclean;

implicit_event_handlers {
  return {
    heartbeat => { },
  };
};

has charge_amount_per_unit => (
  is => 'ro',
  isa => PositiveMillicents,
  required => 1,
  traits => [ qw(Copy) ],
);

# create a replacement when the available funds are no longer enough
# to purchase this many of the commodity
# (if omitted, create replacement when estimated running-out time
# is less than replacement_lead_time)
has low_water_mark => (
  is => 'ro',
  isa => Num,
  predicate => 'has_low_water_mark',
  traits => [ qw(Copy) ],
);

has most_recent_request => (
  is => 'rw',
  isa => PositiveInt,
  traits => [ qw(Copy) ],
);

# Return hold object on success, false on insuficient funds
#
sub _create_hold_for_amount {
  my ($self, $amount, $subsidiary_hold) = @_;

  confess "Hold amount $amount < 0" if $amount < 0;

  # This should have been caught before, in create_hold_for_units
  confess "insufficient funds to satisfy $amount"
    if $amount > $self->unapplied_amount;

  my $hold = $self->ledger->create_transfer({
    type   => 'hold',
    from   => $self,
    to     => $self->ledger->current_journal,
    amount => $amount,
  });

  return $hold;
}

sub create_hold_for_units {
  my ($self, $units_requested) = @_;
  my $units_to_get = $units_requested;
  my $units_remaining = $self->units_remaining;

  my $subsidiary_hold;
  if ($units_remaining < $units_requested) {

    # Can't satisfy request
    return unless $self->has_replacement;

    $subsidiary_hold =
      $self->replacement->create_hold_for_units(
        $units_requested - $units_remaining
      ) or return;
    $units_to_get = $units_remaining;
  }

  my $hold = $self->_create_hold_for_amount(
    $self->charge_amount_per_unit * $units_requested,
    $subsidiary_hold,
  );
  $self->most_recent_request($units_requested);

  unless ($hold) {
    $subsidiary_hold->delete_hold() if $subsidiary_hold;
    return;
  }

  $self->maybe_make_replacement;

  return $hold;
}

sub will_die_soon {
  my ($self) = @_;
  my $low_water_mark =
    $self->has_low_water_mark ? $self->low_water_mark : $self->most_recent_request;
  $self->units_remaining <= $low_water_mark;
}

sub units_remaining {
  my ($self) = @_;
  int($self->unapplied_amount / $self->charge_amount_per_unit);
}

sub create_charge_for_hold {
  my ($self, $hold, $description) = @_;

  croak "No hold provided" unless $hold;
  croak "No charge description provided" unless $description;
  $hold->source->guid eq $self->guid
    or confess "misdirected hold";

  my $now = Moonpig->env->now;

  $self->charge_current_journal({
    desc   => $description,
    amount => $hold->amount,
  });
  $hold->delete;
}

# Total amount of money consumed by me in the past $max_age seconds
sub recent_usage {
  my ($self, $max_age) = @_;

  return $self->accountant->from_consumer($self)
    ->newer_than($max_age)->total;
}

# based on the last $days days of transfers, how long might we expect
# the current funds to last, in seconds?
# If no estimate is possible, return 365d
sub remaining_life {
  my ($self) = @_;
  my $days = 30;
  my $recent_daily_usage = $self->recent_usage($days * 86_400) / $days;
  return 86_400 * 365 if $recent_daily_usage == 0;
  return 86_400 * $self->unapplied_amount / $recent_daily_usage;
}

sub estimated_lifetime {
  my ($self) = @_;
  my $age = Moonpig->env->now - $self->activated_at + $self->remaining_life;
}

sub expiration_date {
  my ($self) = @_;
  return Moonpig->env->now + $self->remaining_life;
}

1;

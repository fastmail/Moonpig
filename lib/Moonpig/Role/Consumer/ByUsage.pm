package Moonpig::Role::Consumer::ByUsage;
# ABSTRACT: a consumer that charges when told to

use Carp qw(confess croak);
use List::Util qw(reduce);
use Moonpig;
use Moonpig::Events::Handler::Method;
use Moonpig::Trait::Copy;
use Moonpig::Types qw(ChargePath);
use Moonpig::Util qw(class days event);
use Moose::Role;
use MooseX::Types::Moose qw(Num);

use Moonpig::Logger '$Logger';

with(
  'Moonpig::Role::Consumer::ChargesBank',
  'Moonpig::Role::HandlesEvents',
  'Moonpig::Role::StubBuild',
);

use Moonpig::Behavior::EventHandlers;
use Moonpig::Types qw(PositiveMillicents Time TimeInterval);

use namespace::autoclean;

implicit_event_handlers {
  return {
    heartbeat => { },
  };
};

has cost_per_unit => (
  is => 'ro',
  isa => PositiveMillicents,
  required => 1,
  traits => [ qw(Copy) ],
);

# create a replacement when the available funds are no longer enough
# to purchase this many of the commodity
# (if omitted, create replacement when estimated running-out time
# is less than old_age)
has low_water_mark => (
  is => 'ro',
  isa => Num,
  predicate => 'has_low_water_mark',
  traits => [ qw(Copy) ],
);

# Return hold object on success, false on insuficient funds
#
sub _create_hold_for_amount {
  my ($self, $amount, $subsidiary_hold) = @_;

  confess "Hold amount $amount < 0" if $amount < 0;

  # This should have been caught before, in create_hold_for_units
  confess "insufficient funds to satisfy $amount"
    unless $self->has_bank && $amount <= $self->unapplied_amount;

  my $hold = $self->ledger->create_transfer({
    type   => 'hold',
    from   => $self->bank,
    to     => $self,
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
    $self->cost_per_unit * $units_requested,
    $subsidiary_hold,
  );

  unless ($hold) {
    $subsidiary_hold->delete_hold() if $subsidiary_hold;
    return;
  }

  {
    my $low_water_mark =
      $self->has_low_water_mark ? $self->low_water_mark : $units_requested;
    if ($self->units_remaining <= $low_water_mark ||
          $self->estimated_lifetime <= $self->old_age) {
      # XXX code duplicated between ByTime and here
      if ($self->has_replacement) {
        $self->replacement->handle_event(
          event('low-funds',
                { remaining_life => $self->estimated_lifetime }
               ));
      } else {
        $self->handle_event(event('consumer-create-replacement',
                                  { timestamp => Moonpig->env->now,
                                    mri => $self->replacement_mri,
                                  }));
      }
    }
  }

  return $hold;
}

sub units_remaining {
  my ($self) = @_;
  int($self->unapplied_amount / $self->cost_per_unit);
}

sub template_like_this {
  my ($self) = @_;

  return {
    class => $self->meta->name,
    arg   => {
      charge_path_prefix => $self->charge_path_prefix(),
      cost_per_unit      => $self->cost_per_unit(),
      ledger             => $self->ledger(),

    $self->has_low_water_mark ?
     (low_water_mark     => $self->low_water_mark()) : (),

      old_age            => $self->old_age(),
      replacement_mri    => $self->replacement_mri(),
      xid                => $self->xid,
    },
  };
}

sub create_charge_for_hold {
  my ($self, $hold, $description) = @_;

  croak "No hold provided" unless $hold;
  croak "No charge description provided" unless $description;
  $hold->target->guid eq $self->guid
    or confess "misdirected hold";
  $self->has_bank
    or confess "charge committed on bankless consumer";

  my $now = Moonpig->env->now;

  $self->ledger->current_journal->charge({
    desc => $description,
    from => $hold->source,
    to   => $self,
    date => $now,
    amount    => $hold->amount,
    charge_path => $self->charge_path,
  });
  $hold->delete;
}

# Total amount of money consumed by me in the past $max_age seconds
sub recent_usage {
  my ($self, $max_age) = @_;

  return $self->accountant->from_bank($self->bank)
    ->newer_than($max_age)->total;
}

# based on the last $days days of transfers, how long might we expect
# the current bank to last, in seconds?
# If no estimate is possible, return 365d
sub estimated_lifetime {
  my ($self) = @_;
  my $days = 30;
  my $recent_daily_usage = $self->recent_usage($days * 86_400) / $days;
  return 86_400 * 365 if $recent_daily_usage == 0;
  return 86_400 * $self->unapplied_amount / $recent_daily_usage;
}

1;

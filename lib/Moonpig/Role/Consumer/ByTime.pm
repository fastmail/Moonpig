package Moonpig::Role::Consumer::ByTime;
use DateTime;
use DateTime::Duration;
use DateTime::Infinite;
use Moose::Role;
use namespace::autoclean;

with(
  'Moonpig::Role::Consumer',
  'Moonpig::Role::HandlesEvents',
);

use Moonpig::Types qw(Millicents);

# How often I charge the bank
has charge_frequency => (
  is => 'ro',
  default => sub { DateTime::Duration->new( days => 1 ) },
  isa => 'DateTime::Duration',
);

# How much I cost to own, in millicents per period
has cost_amount => (
  is => 'ro',
  required => 1,
  isa => 'Num',
);

#  XXX this is period in days, which is not quite right, since a
#  charge of $10 per month or $20 per year is not any fixed number of
#  days, For example a charge of $20 annually, charged every day,
#  works out to 5479 mc per day in common years, but 5464 mc per day
#  in leap years.  -- 2010-10-26 mjd

has cost_period => (
   is => 'ro',
   required => 1,
   isa => 'DateTime::Duration',   # XXX in days
);

# Last time I charged the bank
has last_charge_date => (
  is => 'rw',
  isa => 'DateTime',
#  default => sub { DateTime::Infinite::Past->new },
);

sub last_charge_exists {
  my ($self) = @_;
  return defined($self->last_charge_date);
}

# Set this to force stop object in time
has current_time => (
  is => 'ro',
  isa => 'DateTime',
);

sub now {
  my ($self) = @_;
  $self->current_time || DateTime->now();
}

sub expire_date {
  my ($self) = @_;
  my $bank = $self->bank || return;
  my $remaining = $bank->remaining_amount;
  my $n_full_periods_left = int($remaining/$self->cost_amount); # dimensionless
  return $self->next_charge_date +
      $n_full_periods_left * $self->cost_period;
}

sub next_charge_date {
  my ($self) = @_;
  if ($self->last_charge_exists) {
    return $self->last_charge_date + $self->charge_frequency;
  } else {
    return $self->now;
  }
}

1;

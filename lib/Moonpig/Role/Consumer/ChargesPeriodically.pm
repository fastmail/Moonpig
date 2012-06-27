package Moonpig::Role::Consumer::ChargesPeriodically;
# ABSTRACT: a consumer that issues charges when it gets a heartbeat event

use Carp qw(confess croak);
use Moose::Role;
use Moonpig;
use Moonpig::DateTime;
use Moonpig::Behavior::EventHandlers;
use Moonpig::Events::Handler::Method;
use Moonpig::Types qw(Time TimeInterval);
use Moonpig::Util qw(days);
use Stick::Types qw(StickBool);

with ('Moonpig::Role::HandlesEvents');
requires 'calculate_charge_structs_on';

# Last time I charged
has last_charge_date => (
  is   => 'rw',
  isa  => Time,
  predicate => 'has_last_charge_date',
  traits => [ qw(Copy) ],
);

# How often I issue charges
has charge_frequency => (
  is => 'ro',
  isa     => TimeInterval,
  default => sub { days(1) },
  traits => [ qw(Copy) ],
);

# Very few entities can overdraw their funds, because in almost all
# cases Moonpig requires consumers to be funded. But in a few cases,
# such as Pobox bulk accounts, is useful to allow consumers to
# continue providing service on credit.
has allows_overdrafts => (
  is => 'ro',
  isa => StickBool,
  default => 0,
  coerce => 1,
);

sub charge {
  my ($self, $event) = @_;

  my $now = $event->timestamp;

  # Keep making charges until the next one is supposed to be charged at a time
  # later than now. -- rjbs, 2011-01-12
  CHARGE: until ($self->next_charge_date->follows($now)) {
      my $next = $self->next_charge_date;
      $self->charge_one_day($next);
      $self->last_charge_date($next);
      if ($self->is_expired) {
        $self->replacement->handle_event($event) if $self->replacement;
        last CHARGE;
      }
  }
}

sub charge_one_day {
  my ($self, $now) = @_;

  my $next_charge_date = $self->next_charge_date;

  my @charge_structs = $self->calculate_charge_structs_on( $next_charge_date );

  for my $struct (@charge_structs) {
    $self->charge_current_journal({
      description => $struct->{description},
      date => $next_charge_date,
      amount => $struct->{amount},
      extra_tags => $struct->{extra_tags},
      skip_funds_check => $self->allows_overdrafts,
    });
  }

  if ($self->does('Moonpig::Role::Consumer::MakesReplacement')) {
    $self->maybe_make_replacement;
  }
}

sub next_charge_date {
  my ($self) = @_;

  return $self->activated_at unless $self->has_last_charge_date;
  return $self->last_charge_date + $self->charge_frequency;
}

1;

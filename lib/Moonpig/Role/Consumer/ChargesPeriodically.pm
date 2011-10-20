
package Moonpig::Role::Consumer::ChargesPeriodically;
# ABSTRACT: a consumer that issues charges when it gets a heartbeat event

use Carp qw(confess croak);
use List::MoreUtils qw(natatime);
use Moose::Role;
use Moonpig;
use Moonpig::DateTime;
use Moonpig::Behavior::EventHandlers;
use Moonpig::Events::Handler::Method;
use Moonpig::Types qw(Time TimeInterval);
use Moonpig::Util qw(days);

with ('Moonpig::Role::HandlesEvents');
requires 'calculate_charges_on';

implicit_event_handlers {
  return {
    heartbeat => {
      charge => Moonpig::Events::Handler::Method->new(
        method_name => 'charge',
      ),
    },
    activated => {
      set_up_last_charge_date => Moonpig::Events::Handler::Method->new(
        method_name => 'set_up_last_charge_date',
       ),
    },
  };
};

# Last time I charged the bank
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

sub charge {
  my ($self, $event, $arg) = @_;

  my $now = $event->payload->{timestamp}
    or confess "event payload has no timestamp";

  # Keep making charges until the next one is supposed to be charged at a time
  # later than now. -- rjbs, 2011-01-12
  CHARGE: until ($self->next_charge_date->follows($now)) {
      $self->charge_one_day($now);
      $self->last_charge_date($self->next_charge_date());
  }
}

sub charge_one_day {
  my ($self, $now) = @_;
    # maybe make a replacement, maybe tell it that it will soon inherit the
    # kingdom, maybe do nothing -- rjbs, 2011-01-17

  my $next_charge_date = $self->next_charge_date;

  my @costs = $self->calculate_charges_on( $next_charge_date );

  my $iter = natatime 2, @costs;

  while (my ($desc, $amt) = $iter->()) {
    $self->ledger->current_journal->charge({
      desc => $desc,
      from => $self->bank,
      to   => $self,
      date => $next_charge_date,
      tags => $self->journal_charge_tags,
      amount => $amt,
    });
  }
}

sub set_up_last_charge_date {
  my ($self) = @_;
  unless ($self->has_last_charge_date) {
    $self->last_charge_date( Moonpig->env->now - $self->charge_frequency );
  }
}

sub next_charge_date {
  my ($self) = @_;
  croak "Inactive consumer has no next_charge_date yet"
    unless $self->has_last_charge_date;
  return $self->last_charge_date + $self->charge_frequency;
}

1;

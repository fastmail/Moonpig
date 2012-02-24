package Moonpig::Role::Consumer::ByTime;
# ABSTRACT: a consumer that charges steadily as time passes

use Carp qw(confess croak);
use List::MoreUtils qw(natatime);
use Moonpig;
use Moonpig::DateTime;
use Moonpig::Util qw(class days event sum);
use Moose::Role;
use MooseX::Types::Moose qw(ArrayRef Num);

use Moonpig::Logger '$Logger';
use Moonpig::Trait::Copy;

require Stick::Publisher;
Stick::Publisher->VERSION(0.20110324);
use Stick::Publisher::Publish 0.20110324;

with(
  'Moonpig::Role::Consumer::ChargesPeriodically',
  'Moonpig::Role::Consumer::InvoiceOnCreation',
  'Moonpig::Role::Consumer::MakesReplacement',
  'Moonpig::Role::StubBuild',
);

requires 'charge_pairs_on';

use Moonpig::Behavior::EventHandlers;

use Moonpig::Types qw(PositiveMillicents Time TimeInterval);

use namespace::autoclean;

sub now { Moonpig->env->now() }

sub charge_amount_on {
  my ($self, $date) = @_;

  my %charge_pairs = $self->charge_pairs($date);
  my $amount = sum(values %charge_pairs);

  return $amount;
}

sub initial_invoice_charge_pairs {
  my ($self) = @_;
  my @pairs = $self->charge_pairs_on( Moonpig->env->now );

  my $ratio = $self->proration_period / $self->cost_period;
  $pairs[$_] *= $ratio for grep { $_ % 2 } keys @pairs;

  return @pairs;
}

has cost_period => (
  is => 'ro',
  required => 1,
  isa => TimeInterval,
  traits => [ qw(Copy) ],
);

has proration_period => (
  is   => 'ro',
  isa  => TimeInterval,
  lazy => 1,
  default => sub { $_[0]->cost_period },
);

after BUILD => sub {
  my ($self) = @_;
  Moonpig::X->throw({ ident => 'proration longer than cost period' })
    if $self->proration_period > $self->cost_period;
};

after become_active => sub {
  my ($self) = @_;

  $self->grace_until( Moonpig->env->now  +  $self->grace_period_duration );

  $Logger->log([
    '%s: %s became active; grace until %s, next charge date %s',
    q{} . Moonpig->env->now,
    $self->ident,
    q{} . $self->grace_until,
    q{} . $self->next_charge_date,
  ]);
};

publish expire_date => { } => sub {
  my ($self) = @_;

  $self->is_active ||
    confess "Can't calculate remaining life for inactive consumer";

  my $remaining = $self->unapplied_amount;

  if ($remaining <= 0) {
    return $self->grace_until if $self->in_grace_period;
    return Moonpig->env->now;
  }

  my $n_charge_periods_left
    = int($remaining / $self->calculate_total_charge_amount_on( Moonpig->env->now ));

  return $self->next_charge_date() +
      $n_charge_periods_left * $self->charge_frequency;
};

# returns amount of life remaining, in seconds
sub remaining_life {
  my ($self, $when) = @_;
  $when ||= $self->now();
  $self->expire_date - $when;
}

sub will_die_soon { 0 } # Provided by MakesReplacement

sub estimated_lifetime { $_[0]->proration_period }

################################################################
#
#

has grace_until => (
  is  => 'rw',
  isa => Time,
  clearer   => 'clear_grace_until',
  predicate => 'has_grace_until',
  traits => [ qw(Copy) ],
);

has grace_period_duration => (
  is  => 'rw',
  isa => TimeInterval,
  default => days(3),
  traits => [ qw(Copy) ],
);

sub in_grace_period {
  my ($self) = @_;

  return unless $self->has_grace_until;

  return $self->grace_until >= Moonpig->env->now;
}

################################################################
#
#

around charge => sub {
  my $orig = shift;
  my ($self, @args) = @_;

  return if $self->in_grace_period;
  return unless $self->is_active;

  $self->$orig(@args);
};

around charge_one_day => sub {
  my $orig = shift;
  my ($self, @args) = @_;

  unless ($self->can_make_payment_on( $self->next_charge_date )) {
    $self->expire;
    return;
  }

  $self->$orig(@args);
};

# how much do we charge each time we issue a new charge?
sub calculate_charge_pairs_on {
  my ($self, $date) = @_;

  my $n_periods = $self->cost_period / $self->charge_frequency;

  my @charge_pairs = $self->charge_pairs_on( $date );

  $charge_pairs[$_] /= $n_periods for grep { $_ % 2 } keys @charge_pairs;

  return @charge_pairs;
}

sub calculate_total_charge_amount_on {
  my ($self, $date) = @_;
  my @charge_pairs = $self->calculate_charge_pairs_on( $date );
  my $total_charge_amount = sum map  { $charge_pairs[$_] }
                                grep { $_ % 2 }
                                keys @charge_pairs;

  return $total_charge_amount;
}

sub estimate_cost_for_interval {
  my ($self, $interval) = @_;
  my $iter = natatime 2, $self->initial_invoice_charge_pairs;
  my $total = 0;
  while (my ($desc, $amt) = $iter->()) { $total += $amt }
  return $total * ($interval / $self->cost_period);
}

sub can_make_payment_on {
  my ($self, $date) = @_;
  return
    $self->unapplied_amount >= $self->calculate_total_charge_amount_on($date);
}

1;

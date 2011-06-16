package Moonpig::Role::Consumer::ByTime;
# ABSTRACT: a consumer that charges steadily as time passes

use Carp qw(confess croak);
use List::Util qw(reduce);
use List::MoreUtils qw(natatime);
use Moonpig;
use Moonpig::DateTime;
use Moonpig::Events::Handler::Method;
use Moonpig::Types qw(ChargePath);
use Moonpig::Util qw(class days event);
use Moose::Role;
use MooseX::Types::Moose qw(ArrayRef Num);

use Moonpig::Logger '$Logger';
use Moonpig::Trait::Copy;

require Stick::Publisher;
Stick::Publisher->VERSION(0.20110324);
use Stick::Publisher::Publish 0.20110324;

with(
  'Moonpig::Role::Consumer::ChargesBank',
  'Moonpig::Role::StubBuild',
);

use Moonpig::Behavior::EventHandlers;

use Moonpig::Types qw(PositiveMillicents Time TimeInterval);

use namespace::autoclean;

implicit_event_handlers {
  return {
    heartbeat => {
      charge => Moonpig::Events::Handler::Method->new(
        method_name => 'charge',
      ),
    },
    created => {
      'initial-invoice' => Moonpig::Events::Handler::Method->new(
        method_name => '_invoice',
      ),
    },
  };
};

sub now { Moonpig->env->now() }

# How often I charge the bank
has charge_frequency => (
  is => 'ro',
  isa     => TimeInterval,
  default => sub { days(1) },
  traits => [ qw(Copy) ],
);

# For any given date, what do we think the total costs of ownership for this
# consumer are?  Example:
# [ 'basic account' => dollars(50), 'allmail' => dollars(20), 'support' => .. ]
# This is an arrayref so we can have ordered line items for display.
requires 'costs_on';

sub cost_amount_on {
  my ($self, $date) = @_;

  my %costs = $self->costs_on($date);
  my $amount = reduce { $a + $b } 0, values %costs;

  return $amount;
}

#  XXX this is period in days, which is not quite right, since a
#  charge of $10 per month or $20 per year is not any fixed number of
#  days, For example a charge of $20 annually, charged every day,
#  works out to 5479 mc per day in common years, but 5464 mc per day
#  in leap years.  -- 2010-10-26 mjd

has cost_period => (
   is => 'ro',
   required => 1,
   isa => TimeInterval,
  traits => [ qw(Copy) ],
);

# Last time I charged the bank
has last_charge_date => (
  is   => 'rw',
  isa  => Time,
  predicate => 'has_last_charge_date',
  traits => [ qw(Copy) ],
);

after become_active => sub {
  my ($self) = @_;

  $self->grace_until( Moonpig->env->now  +  $self->grace_period_duration );

  unless ($self->has_last_charge_date) {
    $self->last_charge_date( $self->now() - $self->charge_frequency );
  }

  $Logger->log([
    '%s: %s became active; grace until %s, last charge date %s',
    q{} . Moonpig->env->now,
    $self->ident,
    q{} . $self->grace_until,
    q{} . $self->last_charge_date,
  ]);
};

sub last_charge_exists {
  my ($self) = @_;
  return defined($self->last_charge_date);
}

publish expire_date => { } => sub {
  my ($self) = @_;
  my $bank = $self->bank ||
    confess "Can't calculate remaining life for unfunded consumer";
  my $remaining = $bank->unapplied_amount();

  my $n_charge_periods_left
    = int($remaining / $self->calculate_charge_on( Moonpig->env->now ));

  return $self->next_charge_date() +
      $n_charge_periods_left * $self->charge_frequency;
};

# returns amount of life remaining, in seconds
sub remaining_life {
  my ($self, $when) = @_;
  $when ||= $self->now();
  $self->expire_date - $when;
}

sub next_charge_date {
  my ($self) = @_;
  return $self->last_charge_date + $self->charge_frequency;
}

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

sub charge {
  my ($self, $event, $arg) = @_;

  my $now = $event->payload->{timestamp}
    or confess "event payload has no timestamp";

  return if $self->in_grace_period;
  return unless $self->is_active;

  # Keep making charges until the next one is supposed to be charged at a time
  # later than now. -- rjbs, 2011-01-12
  CHARGE: until ($self->next_charge_date->follows($now)) {
    # maybe make a replacement, maybe tell it that it will soon inherit the
    # kingdom, maybe do nothing -- rjbs, 2011-01-17
    $self->reflect_on_mortality;

    my $next_charge_date = $self->next_charge_date;

    unless ($self->can_make_payment_on( $next_charge_date )) {
      $self->expire;
      return;
    }

    my @costs = $self->calculate_charges_on( $next_charge_date );

    my $iter = natatime 2, @costs;

    while (my ($desc, $amt) = $iter->()) {
      $self->ledger->current_journal->charge({
        desc => $desc,
        from => $self->bank,
        to   => $self,
        date => $next_charge_date,
        amount    => $amt,
        charge_path => $self->charge_path,
      });
    }

    $self->last_charge_date($self->next_charge_date());
  }
}

# how much do we charge each time we issue a new charge?
sub calculate_charges_on {
  my ($self, $date) = @_;

  my $n_periods = $self->cost_period / $self->charge_frequency;

  my @costs = $self->costs_on( $date );

  $costs[$_] /= $n_periods for grep { $_ % 2 } keys @costs;

  return @costs;
}

sub calculate_charge_on {
  my ($self, $date) = @_;
  my @costs = $self->calculate_charges_on( $date );
  my $charge = reduce { $a + $b }
    0, map { $costs[$_] } grep { $_ % 2 } keys @costs;

  return $charge;
}

sub reflect_on_mortality {
  my ($self) = @_;

  return unless $self->has_bank;

  # XXX: noise while testing
  # $Logger->log([ '%s', $self->remaining_life( $tick_time ) ]);

  # if this object does not have long to live...
  my $remaining_life = $self->remaining_life();

  if ($remaining_life <= $self->old_age) {

    # If it has no replacement yet, it should create one
    unless ($self->has_replacement and $remaining_life > 0) {
      $self->handle_event(
        event(
          'consumer-create-replacement',
          {
            mri       => $self->replacement_mri,
          }
        )
       );
    }
  }
}

sub can_make_payment_on {
  my ($self, $date) = @_;
  return $self->amount_in_bank >= $self->calculate_charge_on($date);
}

sub template_like_this {
  my ($self) = @_;

  return {
    class => $self->meta->name,
    arg   => {
      charge_frequency   => $self->charge_frequency(),

      # XXX: NO NO NO, this must be fixed. -- rjbs, 2011-05-17
      # Right now, this is very FixedCost-specific.  We should maybe just move
      # this to FixedCost, in fact...
      cost_amount        => $self->cost_amount_on( Moonpig->env->now ),

      cost_period        => $self->cost_period(),
      old_age            => $self->old_age(),
      replacement_mri    => $self->replacement_mri(),
      xid                => $self->xid,
      charge_description => $self->charge_description(),
      charge_path_prefix => $self->charge_path_prefix(),
      grace_until        => Moonpig->env->now  +  days(3),
    }
  };
}

# My predecessor is running out of money
sub predecessor_running_out {
  my ($self, $event, $args) = @_;
  my $remaining_life = $event->payload->{remaining_life}  # In seconds
    or confess("predecessor didn't advise me how long it has to live");
}

sub _invoice {
  my ($self) = @_;

  my $invoice = $self->ledger->current_invoice;

  my @costs = $self->costs_on( Moonpig->env->now );

  my $iter = natatime 2, @costs;

  while (my ($desc, $amt) = $iter->()) {
    $invoice->add_charge_at(
      class('Charge::Bankable')->new({
        description => $desc,
        amount      => $amt,
        consumer    => $self,
      }),
      $self->charge_path,
    );
  }
}

1;

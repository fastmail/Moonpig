package Moonpig::Role::Consumer::ByTime;
# ABSTRACT: a consumer that charges steadily as time passes

use Carp qw(confess croak);
use Moonpig;
use Moonpig::DateTime;
use Moonpig::Events::Handler::Method;
use Moonpig::Types qw(ChargePath);
use Moonpig::Util qw(days event);
use Moose::Role;
use MooseX::Types::Moose qw(ArrayRef Num);
use namespace::autoclean;

use Moonpig::Logger '$Logger';

with(
  'Moonpig::Role::Consumer',
);

use Moonpig::Behavior::EventHandlers;

use Moonpig::Types qw(Millicents Time TimeInterval);

use namespace::autoclean;

implicit_event_handlers {
  return {
    heartbeat => {
      charge => Moonpig::Events::Handler::Method->new(
        method_name => 'charge'
      ),
    },
    'low-funds' => {
      low_funds_handler => Moonpig::Events::Handler::Method->new(
        method_name => 'predecessor_running_out',
      ),
    },
    'consumer-create-replacement' => {
      create_replacement => Moonpig::Events::Handler::Method->new(
        method_name => 'create_own_replacement',
      ),
    },
  };
};

after BUILD => sub {
  my ($self) = @_;
  unless ($self->has_last_charge_date) {
    $self->last_charge_date($self->now() - $self->charge_frequency);
  }
};

sub now { Moonpig->env->now() }

# How often I charge the bank
has charge_frequency => (
  is => 'ro',
  default => sub { days(1) },
  isa => TimeInterval,
);

# Description for charge.  You will probably want to override this method
has charge_description => (
  is => 'ro',
  isa => 'Str',
  required => 1,
);

# How much I cost to own, in millicents per period
# e.g., a pobox account will have dollars(20) here, and cost_period
# will be one year
has cost_amount => (
  is => 'ro',
  required => 1,
  isa => Millicents,
);

#  XXX this is period in days, which is not quite right, since a
#  charge of $10 per month or $20 per year is not any fixed number of
#  days, For example a charge of $20 annually, charged every day,
#  works out to 5479 mc per day in common years, but 5464 mc per day
#  in leap years.  -- 2010-10-26 mjd

has cost_period => (
   is => 'ro',
   required => 1,
   isa => TimeInterval,
);

# the date is appended to this to make the charge path
# for this consumer's charges
has charge_path_prefix => (
  is => 'ro',
  isa => ChargePath,
  coerce => 1,
  required => 1,
);

# When the object has less than this long to live, it will
# start posting low-balance events to its successor, or to itself if
# it has no successor
has old_age => (
  is => 'ro',
  required => 1,
  isa => TimeInterval,
);

# Last time I charged the bank
has last_charge_date => (
  is => 'rw',
  isa => Time,
  predicate => 'has_last_charge_date',
);

sub last_charge_exists {
  my ($self) = @_;
  return defined($self->last_charge_date);
}

# For a detailed explanation of the logic here, please see the log
# message for 1780fc0a39313eef5adb9936d76dc994f6fa90cd - 2011-01-13 mjd
sub expire_date {
  my ($self) = @_;
  my $bank = $self->bank ||
    confess "Can't calculate remaining life for unfunded consumer";
  my $remaining = $bank->unapplied_amount();

  my $n_charge_periods_left = int($remaining / $self->cost_per_charge);

  return $self->next_charge_date() +
      $n_charge_periods_left * $self->charge_frequency;
}

after expire => sub {
  my ($self) = @_;

  $Logger->log([
    'expiring consumer: %s, %s; %s',
    $self->charge_description,
    $self->ident,
    $self->has_replacement
      ? 'replacement will take over: ' .  $self->replacement->ident
      : 'no replacement exists'
  ]);

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

# This is the schedule of when to warn the owner that money is running out.
# if the number of days of remaining life is listed on the schedule,
# the object will queue a warning event to the ledger.  By default,
# it does this once per week, and also the day before it dies
has complaint_schedule => (
  is => 'ro',
  isa => ArrayRef [ Num ],
  default => sub { [ 28, 21, 14, 7, 1 ] },
);

has last_complaint_date => (
  is => 'rw',
  isa => 'Num',
  predicate => 'has_complained_before',
);

sub issue_complaint_if_necessary {
  my ($self, $remaining_life) = @_;
  my $remaining_days = $remaining_life / 86_400;
  my $sched = $self->complaint_schedule;
  my $last_complaint_issued = $self->has_complained_before
    ? $self->last_complaint_date
    : $sched->[0] + 1;

  # run through each day since the last time we issued a complaint
  # up until now; if any of those days are complaining days,
  # it is time to issue a new complaint.
  my $complaint_due;
  #  warn ">> <$self> $last_complaint_issued .. $remaining_days\n";
  for my $n ($remaining_days .. $last_complaint_issued - 1) {
    $complaint_due = 1, last
      if $self->is_complaining_day($n);
  }

  if ($complaint_due) {
    $self->issue_complaint($remaining_life);
    $self->last_complaint_date($remaining_days);
  }
}

sub is_complaining_day {
  my ($self, $days) = @_;
  confess "undefined days" unless defined $days;
  for my $d (@{$self->complaint_schedule}) {
    return 1 if $d == $days;
  }
  return;
}

sub issue_complaint {
  my ($self, $how_soon) = @_;

  $self->ledger->handle_event(event('send-mkit', {
    kit => 'generic',
    arg => {
      subject => sprintf("YOUR SERVICE RUNS OUT SOON: %s", $self->guid),
      body    => sprintf("YOU OWE US %s\n", $self->cost_amount),

      # This should get names with addresses, unlike the contact-humans
      # handler, which wants envelope recipients.
      to_addresses => [ $self->ledger->contact->email_addresses ],
    },
  }));
}

# XXX this is for testing only; when we figure out replacement semantics
has is_replaceable => (
  is => 'ro',
  isa => 'Bool',
  default => 1,
);

################################################################
#
#

sub charge {
  my ($self, $event, $arg) = @_;

  return unless $self->has_bank;

  my $now = $event->payload->{timestamp}
    or confess "event payload has no timestamp";

  # Keep making charges until the next one is supposed to be charged at a time
  # later than now. -- rjbs, 2011-01-12
  CHARGE: until ($self->next_charge_date->follows($now)) {
    $self->reflect_on_mortality;

    unless ($self->can_make_next_payment) {
      $self->expire;
      return;
    }

    my $next_charge_date = $self->next_charge_date;

    $self->ledger->current_journal->charge({
      desc => $self->charge_description(),
      from => $self->bank,
      to   => $self,
      date => $next_charge_date,
      amount    => $self->cost_per_charge(),
      charge_path => [
        @{$self->charge_path_prefix},
        split(/-/, $next_charge_date->ymd),
      ],
    });

    $self->last_charge_date($self->next_charge_date());
  }
}

sub cost_per_charge {
  my ($self) = @_;

  # Number of cost periods included in each charge
  # (For example, if costs are $10 per 30 days, and we charge daily,
  # there are 1/30 cost periods per day, each costing $10 * 1/30 = $0.33.
  my $n_periods = $self->cost_period / $self->charge_frequency;

  return $self->cost_amount / $n_periods;
}

sub reflect_on_mortality {
  my ($self, $tick_time) = @_;

  return unless $self->has_bank;

  # XXX: noise while testing
  # $Logger->log([ '%s', $self->remaining_life( $tick_time ) ]);

  # if this object does not have long to live...
  if ($self->remaining_life($tick_time) <= $self->old_age) {

    # If it has a replacement R, it should advise R that R will need
    # to take over soon
    if ($self->has_replacement) {
      $self->replacement->handle_event(
        event('low-funds',
              { remaining_life => $self->remaining_life($tick_time) }
             ));
    } else {
      # Otherwise it should create a replacement R
      $self->handle_event(
        event('consumer-create-replacement',
              { timestamp => $tick_time,
                mri => $self->replacement_mri,
              })
       );
    }
  }
}

sub can_make_next_payment {
  my ($self) = @_;
  return $self->unapplied_amount >= $self->cost_per_charge;
}

sub create_own_replacement {
  my ($self, $event, $arg) = @_;

  my $replacement_mri = $event->payload->{mri};

  $Logger->log([ "trying to set up replacement for %s", $self->TO_JSON ]);

  if ($self->is_replaceable && ! $self->has_replacement) {
    my $replacement = $replacement_mri->construct(
      { extra => { self => $self } }
     ) or return;
    $self->replacement($replacement);
    return $replacement;
  }
  return;
}

sub construct_replacement {
  my ($self, $param) = @_;

  my $repl = $self->ledger->add_consumer(
    $self->meta->name,
    {
      cost_amount        => $self->cost_amount(),
      cost_period        => $self->cost_period(),
      old_age            => $self->old_age(),
      replacement_mri    => $self->replacement_mri(),
      ledger             => $self->ledger(),
      charge_description => $self->charge_description(),
      charge_path_prefix => $self->charge_path_prefix(),
      %$param,
  });
}

# My predecessor is running out of money
sub predecessor_running_out {
  my ($self, $event, $args) = @_;
  my $remaining_life = $event->payload->{remaining_life}  # In seconds
    or confess("predecessor didn't advise me how long it has to live");
  $self->issue_complaint_if_necessary($remaining_life);
}

1;

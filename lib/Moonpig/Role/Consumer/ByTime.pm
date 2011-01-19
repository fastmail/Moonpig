package Moonpig::Role::Consumer::ByTime;
# ABSTRACT: a consumer that charges steadily as time passes

use Carp qw(confess croak);
use Moonpig;
use Moonpig::DateTime;
use Moonpig::Events::Handler::Method;
use Moonpig::Types qw(ChargePath);
use Moonpig::Util qw(class days event);
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
        method_name => 'charge',
      ),
    },
    created => {
      'initial-invoice' => Moonpig::Events::Handler::Method->new(
        method_name => '_invoice',
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

# XXX this is for testing only; when we figure out replacement semantics
has is_replaceable => (
  is => 'ro',
  isa => 'Bool',
  default => 1,
);

################################################################
#
#

has grace_until => (
  is  => 'rw',
  isa => Time,
  clearer   => 'clear_grace_until',
  predicate => 'has_grace_until',
);

sub in_grace_period {
  my ($self) = @_;

  return unless $self->has_grace_until;

  return $self->grace_until >= Moonpig->env->now;
}

sub charge {
  my ($self, $event, $arg) = @_;

  my $now = $event->payload->{timestamp}
    or confess "event payload has no timestamp";

  return if $self->in_grace_period;

  # Keep making charges until the next one is supposed to be charged at a time
  # later than now. -- rjbs, 2011-01-12
  CHARGE: until ($self->next_charge_date->follows($now)) {
    # maybe make a replacement, maybe tell it that it will soon inherit the
    # kingdom, maybe do nothing -- rjbs, 2011-01-17
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

# how much do we charge each time we issue a new charge?
sub cost_per_charge {
  my ($self) = @_;

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
      service_uri        => $self->service_uri,
      charge_description => $self->charge_description(),
      charge_path_prefix => $self->charge_path_prefix(),
      grace_until        => Moonpig->env->now  +  days(3),
      %$param,
  });
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

  $invoice->add_charge_at(
    class('Charge::Bankable')->new({
      description => $self->charge_description, # really? -- rjbs, 2011-01-18
      amount      => $self->cost_amount,
      consumer    => $self,
    }),
    $self->charge_path_prefix, # XXX certainly wrong? -- rjbs, 2011-01-18
  );
}

1;

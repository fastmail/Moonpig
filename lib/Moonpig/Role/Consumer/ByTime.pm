package Moonpig::Role::Consumer::ByTime;
# ABSTRACT: a consumer that charges steadily as time passes

use Carp qw(confess croak);
use List::AllUtils qw(all);
use Moonpig;
use Moonpig::DateTime;
use Moonpig::Util qw(class days event sum sumof);
use Moose::Role;
use MooseX::Types::Moose qw(ArrayRef Num);

use Moonpig::Logger '$Logger';
use Moonpig::Trait::Copy;
use POSIX qw(ceil);

require Stick::Publisher;
Stick::Publisher->VERSION(0.20110324);
use Stick::Publisher::Publish 0.20110324;

with(
  'Moonpig::Role::Consumer::ChargesPeriodically',
  'Moonpig::Role::Consumer::InvoiceOnCreation',
  'Moonpig::Role::Consumer::MakesReplacement',
  'Moonpig::Role::Consumer::PredictsExpiration',
  'Moonpig::Role::HandlesEvents',
  'Moonpig::Role::StubBuild',
);

requires 'charge_structs_on';

use Moonpig::Behavior::EventHandlers;
implicit_event_handlers {
  return {
    'heartbeat' => {
      maybe_psync => Moonpig::Events::Handler::Method->new(
        method_name => '_maybe_send_psync_quote',
       ),
    }
  };
};

use Moonpig::Types qw(PositiveMillicents Time TimeInterval);

use namespace::autoclean;

sub now { Moonpig->env->now() }

sub initial_invoice_charge_structs {
  my ($self) = @_;
  my @structs = $self->charge_structs_on( Moonpig->env->now );

  my $ratio = $self->proration_period / $self->cost_period;
  $_->{amount} *= $ratio for @structs;

  return @structs;
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
  # Note *not* copied explicitly; see copy_attr_hash__ decorator below
);

# Fix up the proration period in the copied consumer
around copy_attr_hash__ => sub {
  my ($orig, $self, @args) = @_;
  my $hash = $self->$orig(@args);
  $hash->{proration_period} = $self->_new_proration_period();
  return $hash;
};

sub _new_proration_period {
  my ($self) = @_;
  return $self->is_active
    ? $self->_estimated_remaining_funded_lifetime({
        amount => $self->unapplied_amount, # XXX ???
        ignore_partial_charge_periods => 0,
      })
    : $self->proration_period;
}

after BUILD => sub {
  my ($self) = @_;
  Moonpig::X->throw({ ident => 'proration longer than cost period',
                      payload => {
                        proration_period => $self->proration_period,
                        cost_period => $self->cost_period,
                       }})
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

sub expiration_date;
publish expiration_date => { } => sub {
  $_[0]->bytime_expiration_date;
};

sub bytime_expiration_date {
  my ($self) = @_;

  $self->is_active ||
    confess "Can't calculate remaining life for inactive consumer";

  my $remaining = $self->unapplied_amount;

  if ($remaining <= 0) {
    return $self->grace_until if $self->in_grace_period;
    return Moonpig->env->now;
  } else {
    return $self->next_charge_date +
      $self->_estimated_remaining_funded_lifetime({
        amount => $remaining,
        ignore_partial_charge_periods => 1,
      });
  }
};

# returns amount of life remaining, in seconds
sub remaining_life {
  my ($self, $when) = @_;
  $when ||= $self->now();
  $self->expiration_date - $when;
}

sub will_die_soon { 0 } # The real work is done by MakesReplacement's advice

sub estimated_lifetime {
  my ($self) = @_;

  if ($self->is_active) {
    return $self->expiration_date - $self->activated_at;
  } else {
    return $self->proration_period;
  }
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

  if (
    ($self->was_ever_funded or ! $self->relevant_invoices)
    and $self->does('Moonpig::Role::Consumer::MakesReplacement')
  ) {
    $self->maybe_make_replacement;
  }

  unless ($self->can_make_payment_on( $self->next_charge_date )) {
    $self->expire;
    return;
  }

  $self->$orig(@args);
};

# how much do we charge each time we issue a new charge?
sub calculate_charge_structs_on {
  my ($self, $date) = @_;

  my $n_periods = $self->cost_period / $self->charge_frequency;

  my @charge_structs = $self->charge_structs_on( $date );

  $_->{amount} /= $n_periods for @charge_structs;

  return @charge_structs;
}

sub calculate_total_charge_amount_on {
  my ($self, $date) = @_;
  my @charge_structs = $self->calculate_charge_structs_on( $date );
  my $total_charge_amount = sumof { $_ ->{amount} } @charge_structs;

  return $total_charge_amount;
}

sub minimum_spare_change_amount {
  my ($self) = @_;
  return $self->calculate_total_charge_amount_on( Moonpig->env->now );
}

publish estimate_cost_for_interval => { interval => TimeInterval } => sub {
  my ($self, $arg) = @_;
  my $interval = $arg->{interval};

  my @structs = $self->is_active
              ? $self->charge_structs_on( Moonpig->env->now )
              : $self->initial_invoice_charge_structs;

  my $total = sumof {; $_->{amount} } @structs;
  return $total * ($interval / $self->cost_period);
};

sub can_make_payment_on {
  my ($self, $date) = @_;
  return
    $self->unapplied_amount >= $self->calculate_total_charge_amount_on($date);
}

sub _want_to_live {
  my ($self) = @_;
  if ($self->is_active) {
    return $self->proration_period
             - ($self->next_charge_date - $self->activated_at);
  } else {
    return $self->proration_period;
  }
}

sub _replacement_chain_want_to_live {
  my ($self) = @_;

  my $total = 0;
  for my $entry ($self->replacement_chain) {
    last if $entry->_has_unpaid_charges;
    $total += $entry->_want_to_live;
  }

  return $total;
}

# how much sooner will we run out of money than when we would have
# expected to run out?  Might return a negative value if the consumer
# has too much money. The caller of this function may therefore want
# to clip negative values to 0. - 20120612 mjd
sub _predicted_shortfall {
  my ($self) = @_;

  # First, figure out how much money we have and are due, and assume we're
  # going to get it all. -- rjbs, 2012-03-15
  my $guid = $self->guid;

  my $funds = $self->expected_funds({ include_unpaid_charges => 1 });

  # Next, figure out how long that money will last us.
  my $erfl = $self->_estimated_remaining_funded_lifetime({
    amount => $funds,
    ignore_partial_charge_periods => 0,
  });

  # Next, figure out long we think it *should* last us.
  my $want_to_live = $self->_want_to_live;

  my $shortfall = $want_to_live - $erfl;
  return $shortfall;
}

sub _replacement_chain_expiration_date {
  my ($self, $opts) = @_;

  $opts->{ignore_partial_charge_periods} //= 1;

  return($self->expiration_date +
         $self->_replacement_chain_lifetime($opts));
}

sub _replacement_chain_lifetime {
  my ($self, $_opts) = @_;
  my $opts = { %$_opts };
  $opts->{include_unpaid_charges} //= 0;

  my @chain = $self->replacement_chain;

  unless (all { $_->does('Moonpig::Role::Consumer::ByTime') } @chain) {
    Moonpig::X->throw("replacement in chain cannot predict expiration");
  }

  # XXX 20120605 mjd We shouldn't be ignoring the partial charge
  # period here, which rounds down; we should be rounding UP to the
  # nearest complete charge period, because we are calculating a total
  # expiration date, and each consumer won't be activating its
  # successor until it expires, which occurs at the *end* of the last
  # paid charge period.
  return (sumof {
           $_->_estimated_remaining_funded_lifetime({
             amount => $_->expected_funds({
               include_unpaid_charges => $opts->{include_unpaid_charges},
              }),
             ignore_partial_charge_periods => 1,
           })
         } @chain);
};

# Given an amount of money, estimate how long the money will last
# at current rates of consumption.
#
# If the money will last for a fractional number of charge periods, you
# might or might not want to count the final partial period.
#
# XXX 20120605 ignore_partial_charge_periods should have *three* options:
#  1. include  2. round up  3. round down
#  see long comment in PredictsExpiration.pm for why.
sub _estimated_remaining_funded_lifetime {
  my ($self, $args) = @_;

  # This is for asking what-if questions: what would the estimated remaining
  # funded lifetime be *if* the daily charge were greater by this amount.
  # Normally, of course, this is 0.
  my $charge_adjustment = $args->{charge_adjustment} // 0;

  confess "Missing amount argument to _estimated_remaining_funded_lifetime"
    unless defined $args->{amount};
  Moonpig::X->throw("can't compute remaining lifetime on inactive consumer")
      if $args->{must_be_active} && ! $self->is_active;

  my $each_charge = $self->calculate_total_charge_amount_on( Moonpig->env->now )
                  + $charge_adjustment;

  Moonpig::X->throw("can't compute funded lifetime of negative-cost consumer")
    if $each_charge < 0;

  if ($each_charge == 0) {
    Moonpig::X->throw({
      ident => "can't compute funded lifetime of zero-cost consumer",
      payload => {
        consumer_guid => $self->guid,
        ledger_guid   => $self->ledger->guid,
      },
    });
  }

  my $periods     = $args->{amount} / $each_charge;
  $periods = int($periods) if $args->{ignore_partial_charge_periods};

  return $periods * $self->charge_frequency;
}

has last_psync_shortfall => (
  is => 'rw',
  isa => TimeInterval,
  predicate => 'has_last_psync_shortfall',
  traits => [ qw(Copy) ],
);

sub reset_last_psync_shortfall {
  my ($self) = @_;
  $self->last_psync_shortfall($self->_predicted_shortfall);
}

sub _maybe_send_psync_quote {
  my ($self) = @_;
  return unless $self->is_active;
  return unless grep(! $_->is_abandoned, $self->all_charges) > 0;

  my $shortfall = $self->_predicted_shortfall;
  my $had_last_shortfall = $self->has_last_psync_shortfall;
  my $last_shortfall = $self->last_psync_shortfall // 0;

  # If you're going to run out of funds during your final charge
  # period, we don't care.  In general, we plan to have
  # charge_frequency stick with its default value always: days(1).  If
  # you were to use a days(30) charge frequency, this could mean that
  # someone could easily miss 29 days of service, which is potentially
  # more obnoxious than losing 23 hours. -- rjbs, 2012-03-16
  return if abs($shortfall - $last_shortfall) < $self->charge_frequency;

  $self->last_psync_shortfall($shortfall);
  return if ! $had_last_shortfall && $shortfall <= 0;

  my @old_quotes = $self->ledger->find_old_psync_quotes($self->xid);

  my $notice_info = {

    # OLD date is the one we had before the service upgrade, which will be
    # RESTORED if the user pays the invoice
    old_expiration_date => Moonpig->env->now +
      $self->_want_to_live +
      $self->_replacement_chain_want_to_live,

    # NEW date is the one caused by the service upgrade, which will
    # PERSIST if the user DOES NOT pay the invoice
    new_expiration_date => $self->replacement_chain_expiration_date,
  };

  # Notify followers that we have already handled this shortfall
  # so they don't send another notice on becoming active.
  for my $c ($self->replacement_chain) {
    $c->reset_last_psync_shortfall if $c->can('reset_last_psync_shortfall');
  }

  $_->mark_abandoned() for @old_quotes;

  my @chain = ($self, $self->replacement_chain);

  if (
    (grep { $_->_has_unpaid_charges } @chain)
    &&
    $self->does('Moonpig::Role::Consumer::InvoiceOnCreation')
  ) {
    die "not psyncing with shortfall $last_shortfall -> $shortfall";
  }

  if ($shortfall > 0) {
    $self->ledger->start_quote({ psync_for_xid => $self->xid });
    $self->_issue_psync_charge();
    $_->_issue_psync_charge() for $self->replacement_chain;
    $notice_info->{quote} = $self->ledger->end_quote($self);
  }

  $self->ledger->_send_psync_email($self, $notice_info);
}

sub _issue_psync_charge {
  my ($self) = @_;
  my $shortfall = $self->_predicted_shortfall;
  my $shortfall_days = ceil($shortfall / days(1));
  my $amount = $self->estimate_cost_for_interval({ interval => $shortfall });
  $self->charge_current_invoice({
    extra_tags => [ 'moonpig.psync' ],
    description => sprintf("Shortfall of $shortfall_days %s",
                           $shortfall_days == 1 ? "day" : "days"),
    amount => $amount,
  }) if $amount > 0;
}

1;

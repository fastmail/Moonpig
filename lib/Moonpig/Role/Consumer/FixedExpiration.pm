package Moonpig::Role::Consumer::FixedExpiration;
# ABSTRACT: a consumer that expires automatically on a particular date
use Moose::Role;

use List::AllUtils qw(all first);
use MooseX::Types::Moose qw(Str);
use Moonpig::Types qw(PositiveMillicents Time);

with(
  'Moonpig::Role::Consumer',
  'Moonpig::Role::Consumer::PredictsExpiration',
);

use namespace::autoclean;

use Moonpig::Behavior::EventHandlers;

sub charge {
  my ($self) = @_;
  return if $self->is_expired;
  $self->expire if $self->expiration_date <= Moonpig->env->now;
}

sub remaining_life {
  my ($self, $when) = @_;
  $when ||= Moonpig->env->now;
  my $diff = $self->expiration_date - $when;
  return $diff < 0 ? 0 : $diff;
}

sub estimated_lifetime {
  my ($self) = @_;
  return $self->expiration_date - $self->activated_at;
}

sub _expected_funded_expiration_behavior   { $_[0]->expiration_date }
sub _expected_unfunded_expiration_behavior { 0 }

sub _has_unpaid_charges {
  my ($self) = @_;

  my @unpaid_invoices = grep { $_->is_unpaid && ! $_->is_abandoned }
                        $self->relevant_invoices;

  return !! @unpaid_invoices;
}

sub _replacement_chain_expiration_date {
  my ($self, $arg) = @_;

  my @chain = ($self, $self->replacement_chain);

  my $exp_date = Moonpig->env->now;

  CONSUMER: for my $i (0 .. $#chain) {
    my $this = $chain[$i];

    if ($this->does('Moonpig::Role::Consumer::FixedExpiration')) {
      my $behavior = $this->_has_unpaid_charges
                   ? $this->_expected_unfunded_expiration_behavior
                   : $this->_expected_funded_expiration_behavior;

      my $this_exp_date;

      if ( Time->check($behavior) ) {
        $this_exp_date = $behavior;
      } else {
        $this_exp_date = $exp_date + $behavior;
      }

      if ($this_exp_date > $exp_date) {
        $exp_date = $this_exp_date;
      }

      next CONSUMER;
    } elsif ($this->does('Moonpig::Role::Consumer::ByTime')) {
      my @tail = @chain[ $i .. $#chain ];

      unless (all { $_->does('Moonpig::Role::Consumer::ByTime') } @tail) {
        Moonpig::X->throw("replacement chain can't predict expiration date");
      }

      # This had been done with a sumof, but I think there's a topic leak
      # somewhere. -- rjbs, 2012-08-23
      for my $consumer (@tail) {
        $exp_date
          = $exp_date + $consumer->_estimated_remaining_funded_lifetime(
          {
            amount => $consumer->expected_funds({
              include_unpaid_charges => $arg->{include_unpaid_charges},
            }),
            ignore_partial_charge_periods => 1,
          }
          );
      }

      last CONSUMER;
    }

    Moonpig::X->throw("replacement chain can't predict expiration date");
  }

  return $exp_date;
}

sub _estimated_remaining_funded_lifetime {
  my ($self) = @_;

  Moonpig::X->throw("can't compute remaining lifetime on inactive consumer")
    unless $self->is_active;

  return $self->remaining_life;
}

1;

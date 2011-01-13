package Moonpig::Role::Consumer::ByUsage;
# ABSTRACT: a consumer that charges when told to

use Carp qw(confess croak);
use Moonpig;
use Moonpig::Events::Handler::Method;
use Moonpig::Types qw(CostPath);
use Moonpig::Util qw(days event);
use Moose::Role;
use MooseX::Types::Moose qw(Num);

use Moonpig::Logger '$Logger';

with(
  'Moonpig::Role::Consumer',
  'Moonpig::Role::HandlesEvents',
  'Moonpig::Role::StubBuild',
);

use Moonpig::Behavior::EventHandlers;
use Moonpig::Types qw(Millicents Time TimeInterval);

use namespace::autoclean;

implicit_event_handlers {
  return {
    heartbeat => { },
    low_funds_check => Moonpig::Events::Handler::Method->new(
      method_name => 'check_low_funds'
    ),
  };
};

has low_water_line => (
  is => 'ro',
  isa => Num,
);

has rate_schedule => (
  is => 'ro',
  does => 'Moonpig::Role::RateSchedule',
  required => 1,
  handles => { cost => 'cost_of' },
);

# Return hold object on success, false on insuficient funds
sub create_hold_for_amount {
  my ($self, $amount) = @_;

  confess "Hold amount $amount < 0" if $amount < 0;
  return unless $self->has_bank && $amount <= $self->unapplied_amount;

  my $hold = class('Hold')->new(
    bank => $self->bank,
    consumer => $self,
    allow_deletion => 1,
    amount => $amount,
  );

  return $hold;
}

sub create_hold_for_units {
  my ($self, $n_units) = @_;
  $self->create_hold_for_amount($self->cost($n_units));
}

1;

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
  };
};

has cost_per_unit => (
  is => 'ro',
  isa => Millicents,
  required => 1,
);

# create a replacement when the available funds are no longer enough
# to purchase this many of the commodity
# (if omitted, create replacement when not enough funds remain to buy
# another batch of the same size as the last batch bought)
has low_water_mark => (
  is => 'ro',
  isa => Num,
  predicate => 'has_low_water_mark',
);

# Return hold object on success, false on insuficient funds
# XXX when does the charge get created??
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

  {
    my $not_much_left;
    if ($self->has_low_water_mark) {
      $not_much_left = $self->n_units_remaining <= $self->low_water_mark;
    } else {
      $not_much_left = $self->n_unapplied_amount <= $amount;
    }
    $not_much_left and $self->handle_event(event('consumer-create-replacement'));
  }

  return $hold;
}

sub create_hold_for_units {
  my ($self, $n_units) = @_;
  $self->create_hold_for_amount($self->cost_per_unit * $n_units);
}

sub units_remaining {
  int($self->unapplied_amount / $self->cost_per_unit);
}

sub construct_replacement {
  my ($self, $param) = @_;

  my $repl = $self->ledger->add_consumer(
    $self->meta->name,
    {
      cost_per_unit      => $self->cost_per_unit(),
      low_water_mark     => $self->low_water_mark(),
      replacement_mri    => $self->replacement_mri(),
      ledger             => $self->ledger(),
      cost_path_prefix   => $self->cost_path_prefix(),
      %$param,
  });
}

1;

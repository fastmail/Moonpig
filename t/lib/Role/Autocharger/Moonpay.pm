package t::lib::Role::Autocharger::Moonpay;
use Moose::Role;

with 'Moonpig::Role::Autocharger';

use Moonpig::Behavior::Packable;
use Moonpig::Types qw(NonNegativeMillicents PositiveMillicents);
use Moonpig::Util qw(class dollars);

has source_ident => (
  is => 'rw',
  isa => 'Str',
  default => "something or other",
);

has amount_available => (
  is  => 'rw',
  isa => NonNegativeMillicents,
  default => 0,
);

has minimum_charge_amount => (
  is => 'ro',
  isa => PositiveMillicents,
  default => dollars(1),
);

sub charge_into_credit {
  my ($self, $arg) = @_;

  my $amount = $arg->{amount};
  PositiveMillicents->assert_valid($amount);

  return unless $amount >= $self->minimum_charge_amount;

  my $on_hand = $self->amount_available;
  $on_hand -= $amount;

  return unless $on_hand >= 0;

  $self->amount_available($on_hand);

  my $credit = $self->ledger->add_credit(
    class(qw(Credit::Simulated)),
    { amount => $amount },
  );
}

sub _class_subroute { ... }

PARTIAL_PACK {
  return {
    amount_available => $_[0]->amount_available,
    source_ident     => $_[0]->source_ident,
  }
};

1;

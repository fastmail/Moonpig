package t::lib::Role::Autocharger::Moonpay;
use Moose::Role;

with 'Moonpig::Role::Autocharger';

use Moonpig::Types qw(PositiveMillicents);
use Moonpig::Util qw(class dollars);

has amount_available => (
  is  => 'rw',
  isa => NonNegativeMillicents,
  default => 0,
);

has minimum_charge_amount => (
  is => 'ro',
  isa => PositiveMillicents,
  default => 0,
);

sub charge_into_credit {
  my ($self, $arg) = @_;

  my $amount = $arg->{amount};
  PositiveMillicents->assert_valid($amount);

  return unless $amount >= $self->minimum_charge_amount;

  my $on_hand = $self->amount_available;
  return unless $amount <= $self->amount_available;

  my $credit = $ledger->add_credit(
    class(qw(Credit::Simulated)),
    { amount => $amount },
  );
}

1;

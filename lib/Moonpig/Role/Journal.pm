package Moonpig::Role::Journal;
use Carp qw(croak);
use Moonpig::Transfer;
use Moose::Role;

with(
  'Moonpig::Role::CostTreeContainer' => { charges_handle_events => 0 },
  'Moonpig::Role::LedgerComponent',
  'Moonpig::Role::HandlesEvents',
);

use namespace::autoclean;


# from: source of money transfer
# to: destination of money transfer
# amount: amount of transfer
# desc: charge descriptiopn
# cost_path: path in current journal cost tree to add charge
# when: when to record charge (optional)
sub charge {
  my ($self, $args) = @_;

  { my $FAIL = "";
    for my $reqd (qw(from to amount desc cost_path)) {
      $FAIL .= __PACKAGE__ . "::charge missing required '$reqd' argument"
        unless $args->{$reqd};
    }
    croak $FAIL if $FAIL;
  }

  # create transfer
  $self->transfer_factory->new(
    { amount => $args->{amount},
      bank => $args->{from},
      consumer => $args->{to},
    });

  my $charge = $self->charge_factory->new({
    description => $args->{desc},
    amount => $args->{amount},
    date => $args->{when} || Moonpig->env->now(),
  });

  $self->add_charge_at(
    $charge, $args->{cost_path},
  );

  return $charge;
}

sub transfer_factory {
  "Moonpig::Transfer";
}

sub charge_factory {
  "Moonpig::Charge::Basic";
}

1;

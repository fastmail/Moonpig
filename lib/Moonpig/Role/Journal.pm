package Moonpig::Role::Journal;
# ABSTRACT: a journal of charges made by consumers against banks

use Carp qw(croak);
use Moonpig::Transfer;
use Moonpig::Util qw(class);
use Moose::Role;

use Moonpig::Logger '$Logger';

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

  $Logger->log([
    "adding charge at %s for %s",
    join(q{.}, @{ $args->{cost_path} }),
    $charge->amount,
  ]);

  return $charge;
}

sub transfer_factory {
  "Moonpig::Transfer";
}

sub charge_factory {
  class('Charge');
}

1;

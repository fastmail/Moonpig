package Moonpig::Role::Journal;
# ABSTRACT: a journal of charges made by consumers against banks

use Carp qw(croak);
use Moonpig::Util qw(class);
use Moose::Role;

use Moonpig::Logger '$Logger';

with(
  'Moonpig::Role::ChargeTreeContainer' => { charges_handle_events => 0 },
  'Moonpig::Role::LedgerComponent',
  'Moonpig::Role::HandlesEvents',
  'Moonpig::Role::HasGuid',
);

use namespace::autoclean;


# from: source of money transfer
# to: destination of money transfer
# amount: amount of transfer
# desc: charge descriptiopn
# charge_path: path in current journal cost tree to add charge
# when: when to record charge (optional)
sub charge {
  my ($self, $args) = @_;

  { my $FAIL = "";
    for my $reqd (qw(from to amount desc charge_path)) {
      $FAIL .= __PACKAGE__ . "::charge missing required '$reqd' argument"
        unless $args->{$reqd};
    }
    croak $FAIL if $FAIL;
  }

  # create transfer
  $self->ledger->transfer(
    { amount => int($args->{amount}), # Round in favor of customer
      from   => $args->{from},
      to     => $args->{to},
    });

  my $charge = $self->charge_factory->new({
    description => $args->{desc},
    amount => $args->{amount},
    date => $args->{when} || Moonpig->env->now(),
  });

  $self->add_charge_at(
    $charge, $args->{charge_path},
  );

  $Logger->log([
    "adding charge at %s for %s",
    join(q{.}, @{ $args->{charge_path} }),
    $charge->amount,
  ]);

  return $charge;
}

sub charge_factory {
  class('Charge');
}

1;

package Moonpig::Role::Journal;
# ABSTRACT: a journal of how consumers funds are spent

use Carp qw(croak);
use Moonpig::Util qw(class);
use Moose::Role;

use Moonpig::Logger '$Logger';

with(
  'Moonpig::Role::HasCharges' => { charge_role => 'JournalCharge' },
  'Moonpig::Role::CanTransfer' => { transferer_type => "journal" },
  'Moonpig::Role::LedgerComponent',
  'Moonpig::Role::HandlesEvents',
  'Moonpig::Role::HasGuid',
);

use namespace::autoclean;

sub accepts_charge {
  my ($self, $charge) = @_;
  $charge->does("Moonpig::Role::JournalCharge");
}

# from: source of money transfer
# to: destination of money transfer
# amount: amount of transfer
# desc: charge descriptiopn
# tags: what tags to put on the charge
# when: when to record charge (optional)
sub charge {
  my ($self, $args) = @_;

  { my $FAIL = "";
    for my $reqd (qw(from to amount desc tags)) {
      $FAIL .= __PACKAGE__ . "::charge missing required '$reqd' argument"
        unless $args->{$reqd};
    }
    croak $FAIL if $FAIL;
  }

  # create transfer
  $self->ledger->transfer({
    amount => int($args->{amount}), # Round in favor of customer
    from   => $args->{from},
    to     => $args->{to},

    skip_funds_check => $args->{skip_funds_check},
  });

  my $charge = $self->charge_factory->new({
    description => $args->{desc},
    amount => $args->{amount},
    date => $args->{when} || Moonpig->env->now(),
    tags => $args->{tags},
  });

  $self->add_charge($charge);

  $Logger->log([
    "adding charge for %s tagged %s",
    $charge->amount,
    join(q{ }, @{ $args->{tags} }),
  ]);

  return $charge;
}

sub charge_factory {
  class('JournalCharge');
}

1;

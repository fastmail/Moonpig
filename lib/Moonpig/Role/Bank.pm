package Moonpig::Role::Bank;
# ABSTRACT: a bunch of money held by a ledger and used up by consumers
use Moose::Role;
with(
 'Moonpig::Role::HasGuid',
 'Moonpig::Role::LedgerComponent',
 'Moonpig::Role::StubBuild',
 'Moonpig::Role::CanTransfer' => { transferer_type => "bank" },
);

use Moonpig::Logger '$Logger';
use Moonpig::Types qw(Ledger PositiveMillicents);

use namespace::autoclean;

sub amount {
  my ($self) = @_;
  my $xferset = $self->ledger->accountant->select({ target => $self });
  return $xferset->total;
}

sub unapplied_amount {
  my ($self) = @_;
  return $self->amount - $self->accountant->from_bank($self)->total;
}

1;

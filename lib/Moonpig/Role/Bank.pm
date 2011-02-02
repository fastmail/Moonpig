package Moonpig::Role::Bank;
# ABSTRACT: a bunch of money held by a ledger and used up by consumers
use Moose::Role;
with(
 'Moonpig::Role::HasGuid',
 'Moonpig::Role::LedgerComponent',
 'Moonpig::Role::StubBuild',
 'Moonpig::Role::CanTransfer' => { transferer_type => "bank" },
);

use List::Util qw(reduce);
use Moonpig::Logger '$Logger';
use Moonpig::Types qw(Ledger PositiveMillicents);

use namespace::autoclean;

# The initial amount in the piggy bank
# The amount *available* is this initial amount,
# minus all the charges that transfer from this bank.
has amount => (
  is  => 'ro',
  isa =>  PositiveMillicents,
  coerce   => 1,
  required => 1,
);

sub unapplied_amount {
  my ($self) = @_;
  return $self->amount - $self->accountant->from_bank($self)->total;
}

1;

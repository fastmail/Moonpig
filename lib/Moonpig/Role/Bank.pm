package Moonpig::Role::Bank;
# ABSTRACT: a bunch of money held by a ledger and used up by consumers
use Moose::Role;
with(
 'Moonpig::Role::HasGuid',
 'Moonpig::Role::LedgerComponent',
 'Moonpig::Role::StubBuild',
 'Moonpig::Role::CanTransfer' => { transfer_type_id => "bank" },
);

use List::Util qw(reduce);
use Moonpig::Logger '$Logger';
use Moonpig::Types qw(Ledger Millicents);

use namespace::autoclean;

# The initial amount in the piggy bank
# The amount *available* is this initial amount,
# minus all the charges that transfer from this bank.
has amount => (
  is  => 'ro',
  isa =>  Millicents,
  coerce   => 1,
  required => 1,
);

sub unapplied_amount {
  my ($self) = @_;
  my @xfers = $self->accountant->from_bank($self)->all;

  my $total = reduce { $a + $b } 0, (map {; $_->amount } @xfers);

  return $self->amount - $total;
}

1;

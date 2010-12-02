package Moonpig::Role::Bank;
use Moose::Role;
with(
 'Moonpig::Role::HasGuid',
 'Moonpig::Role::LedgerComponent',
);

use List::Util qw(reduce);
use Moonpig::Types qw(Ledger Millicents);
use Moonpig::Transfer;

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
  my $xfers = Moonpig::Transfer->all_for_bank($self);

  my $xfer_total = reduce { $a + $b } 0, (map {; $_->amount } @$xfers);

  return $self->amount - $xfer_total;
}

# mechanism to get xfers

1;

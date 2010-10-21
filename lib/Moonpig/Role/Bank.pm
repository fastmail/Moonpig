package Moonpig::Role::Bank;
use Moose::Role;
with(
  'Moonpig::Role::HasGuid',
);

use List::Util qw(reduce);
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

sub remaining_amount {
  my ($self) = @_;
  my $xfers = Moonpig::Transfer->transfers_for_bank($self);

  my $xfer_total = reduce { $a + $b } 0, (map {; $_->amount } @$xfers);

  return $self->amount - $xfer_total;
}

has ledger => (
  is   => 'ro',
  isa  => Ledger,
  required => 1,
);

# mechanism to get xfers

1;

package Moonpig::Role::Bank;
use Moose::Role;
with(
  'Moonpig::Role::HasGuid',
);

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

sub outstanding_balance {
  # find all transactions targeting this piggy bank
  # sum them, and deduct from the ->amount.
}

has ledger => (
  is   => 'ro',
  isa  => Ledger,
  required => 1,
);

# mechanism to get xfers

1;

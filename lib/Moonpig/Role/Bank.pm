package Moonpig::Role::Bank;
# ABSTRACT: a bunch of money held by a ledger and used up by consumers
use Moose::Role;
with(
 'Moonpig::Role::HasGuid',
 'Moonpig::Role::LedgerComponent',
 'Moonpig::Role::StubBuild',
);

use List::Util qw(reduce);
use Moonpig::Logger '$Logger';
use Moonpig::Types qw(Ledger PositiveMillicents);

use Moonpig::Hold;
use Moonpig::Transfer;
use Moonpig::Transfer::BankCredit;

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
  my $consumer_xfers = Moonpig::Transfer->all_for_bank($self);
  my $hold_xfers     = Moonpig::Hold->all_for_bank($self);
  my $credit_xfers   = Moonpig::Transfer::BankCredit->all_for_bank($self);

  my $xfer_total = reduce { $a + $b } 0,
                   (map {; $_->amount } @$consumer_xfers, @$credit_xfers,
                   @$hold_xfers);

  return $self->amount - $xfer_total;
}

# mechanism to get xfers

1;

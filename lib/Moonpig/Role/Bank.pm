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

after BUILD => sub {
  my ($self) = @_;
  $Logger->log([
    'created new bank %s (%s)',
    $self->guid,
    $self->meta->name,
  ]);
};

# mechanism to get xfers

1;

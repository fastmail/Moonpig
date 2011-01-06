package Moonpig::Role::Refund;
use Moose::Role;

with(
  'Moonpig::Role::LedgerComponent',
  'Moonpig::Role::HasGuid',
  'Moonpig::Role::Payable',
);

use List::Util qw(reduce);

use Moonpig::CreditApplication;

use namespace::autoclean;

sub amount {
  my ($self) = @_;

  my $xfers = Moonpig::CreditApplication->all_for_payable($self);

  my $xfer_total = reduce { $a + $b } 0, (map {; $_->amount } @$xfers);

  return $xfer_total;
}

1;

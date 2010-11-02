package Moonpig::Role::Payment;
use Moose::Role;

with 'Moonpig::Role::HasGuid';

use List::Util qw(reduce);

use Moonpig::Types qw(Millicents);

use namespace::autoclean;

has amount => (
  is  => 'ro',
  isa => Millicents,
  coerce => 1,
);

sub unapplied_amount {
  my ($self) = @_;
  my $xfers = Moonpig::Transfer->transfers_for_bank($self);

  my $xfer_total = reduce { $a + $b } 0, (map {; $_->amount } @$xfers);

  return $self->amount - $xfer_total;
}

1;

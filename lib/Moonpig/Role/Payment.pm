package Moonpig::Role::Payment;
use Moose::Role;

use Moonpig::Types qw(Millicents);

use namespace::autoclean;

has amount => (
  is  => 'ro',
  isa => Millicents,
  coerce => 1,
);

has applied_to => (
  is   => 'ro',
  does   => 'Moonpig::Role::Invoice',
  writer    => '_apply_to',
  predicate => 'is_applied',
);

sub apply_to__ {
  my ($self, $invoice) = @_;

  Moonpig::X->throw('double payment application') if $self->is_applied;
  $self->_apply_to($invoice);
}

1;

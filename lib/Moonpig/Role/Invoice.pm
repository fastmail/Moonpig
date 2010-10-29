package Moonpig::Role::Invoice;
use Moose::Role;

with 'Moonpig::Role::CostTreeContainer';

use namespace::autoclean;

sub finalize_and_send {
  my ($self) = @_;

  $self->close;

  # $self->ledger->
}

1;

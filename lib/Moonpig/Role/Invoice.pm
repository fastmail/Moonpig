package Moonpig::Role::Invoice;
use Moose::Role;

with 'Moonpig::Role::CostTreeContainer';

use Moonpig::Util qw(event);

use namespace::autoclean;

sub finalize_and_send {
  my ($self) = @_;

  $self->close;

  $self->ledger->handle_event( event('send-invoice', { invoice => $self }) );
}

1;

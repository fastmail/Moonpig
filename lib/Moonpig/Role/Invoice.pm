package Moonpig::Role::Invoice;
use Moose::Role;

with(
  'Moonpig::Role::CostTreeContainer',
  'Moonpig::Role::LedgerComponent',
  'Moonpig::Role::HandlesEvents',
  'Moonpig::Role::HasGuid',
  'Moonpig::Role::Payable',
);

use Moonpig::CreditApplication;
use Moonpig::Util qw(event);
use Moonpig::Types qw(Credit);
use Moonpig::X;

use namespace::autoclean;

sub finalize_and_send {
  my ($self) = @_;

  $self->close;

  $self->ledger->handle_event( event('send-invoice', { invoice => $self }) );
}

has paid => (
  isa => 'Bool',
  init_arg => undef,
  default  => 0,
  reader   => 'is_paid',
  traits   => [ 'Bool' ],
  handles  => {
    mark_paid => 'set',
    is_unpaid => 'not',
  },
);

1;

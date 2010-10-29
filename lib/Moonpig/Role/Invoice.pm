package Moonpig::Role::Invoice;
use Moose::Role;

with(
  'Moonpig::Role::CostTreeContainer',
  'Moonpig::Role::HandlesEvents',
);

use Moonpig::Util qw(event);
use Moonpig::Types qw(Payment);
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

sub accept_payment {
  my ($self, $payment) = @_;

  Payment->assert_valid($payment);

  Moonpig::X->throw('payment for open invoice') if $self->is_open;

  # XXX: This is only until we implement partial payment and overpayment.
  # -- rjbs, 2010-10-29
  Moonpig::X->throw('payment amount mismatch')
    unless $payment->amount == $self->total_amount;

  $payment->apply_to__($self);

  $self->handle_event(event('invoice-paid'));

  $self->mark_paid;
}

1;

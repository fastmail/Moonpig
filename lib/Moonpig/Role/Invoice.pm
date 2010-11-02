package Moonpig::Role::Invoice;
use Moose::Role;

with(
  'Moonpig::Role::CostTreeContainer',
  'Moonpig::Role::HandlesEvents',
  'Moonpig::Role::HasGuid',
  'Moonpig::Role::Payable',
);

use Moonpig::PaymentApplication;
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

  # XXX: totally not good; placeholder for new application -- rjbs, 2010-11-02
  Moonpig::PaymentApplication->new({
    payment => $payment,
    payable => $self,
    amount  => $payment->amount,
  });

  $self->handle_event(event('invoice-paid'));

  $self->mark_paid;
}

1;

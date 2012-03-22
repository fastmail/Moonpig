package Moonpig::Role::Credit::Refundable;
# ABSTRACT: a credit that can be refunded
use Moose::Role;

with('Moonpig::Role::Credit');

use Moonpig::Util qw(class);

use namespace::autoclean;

requires 'issue_refund';

sub refund_unapplied_amount {
  my ($self) = @_;

  Moonpig::X->throw("can't refund more than ledger's amount available")
    unless $self->unapplied_amount <= $self->ledger->amount_available;

  $self->issue_refund;

  my $refund = $self->ledger->add_debit(class(qw(Debit::Refund)));

  $self->ledger->create_transfer({
    type  => 'debit',
    from  => $self,
    to    => $refund,
    amount  => $self->unapplied_amount,
  });

  return $refund;
}

1;

package Moonpig::Role::Credit::Refundable;
# ABSTRACT: a credit that can be refunded
use Moose::Role;

with('Moonpig::Role::Credit');

use Moonpig::Util qw(class);

use namespace::autoclean;

requires 'issue_refund';

sub refund_unapplied_amount {
  my ($self) = @_;

  $self->issue_refund;

  my $refund = $self->ledger->add_refund(
    class(qw(Refund)),
    {
      ledger => $self->ledger,
    },
  );

  $self->ledger->create_transfer({
    type  => 'refund',
    from  => $self,
    to    => $refund,
    amount  => $self->unapplied_amount,
  });

  return $refund;
}

1;

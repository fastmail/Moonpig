package Moonpig::Role::Credit::Refundable;
# ABSTRACT: a credit that can be refunded
use Moose::Role;

with('Moonpig::Role::Credit');

use List::AllUtils qw(min);
use Moonpig::Util qw(class);

use Stick::Publisher 0.307;
use Stick::Publisher::Publish 0.307;

use namespace::autoclean;

requires 'issue_refund'; # $credit->issue_refund($amount);

publish refund_maximum_refundable_amount => {
  -http_method => 'post',
  -path        => 'refund',
} => sub {
  my ($self) = @_;

  my $amount = min($self->unapplied_amount, $self->ledger->amount_available);
  return unless $amount > 0;

  $self->_refund($amount);
};

sub _refund {
  my ($self, $amount) = @_;

  Moonpig::X->throw("can't refund more than ledger's amount available")
    if $amount > $self->ledger->amount_available;

  $self->issue_refund( $amount );

  my $refund = $self->ledger->add_debit(class(qw(Debit::Refund)));

  $self->ledger->create_transfer({
    type  => 'debit',
    from  => $self,
    to    => $refund,
    amount  => $amount,
  });

  return $refund;
}

sub refund_unapplied_amount {
  my ($self) = @_;
  $self->_refund($self->unapplied_amount);
}

1;

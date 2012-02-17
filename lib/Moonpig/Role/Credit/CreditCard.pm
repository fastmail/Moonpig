package Moonpig::Role::Credit::CreditCard;
# ABSTRACT: credit received from credit card
use Moose::Role;

use Moonpig::Types qw(TrimmedSingleLine);

use namespace::autoclean;

with 'Moonpig::Role::Credit::Refundable';

sub as_string {
  my ($self) = @_;
  return sprintf 'Credit card transaction <%s>',
    $self->transaction_id;
}

has transaction_id => (
  is  => 'ro',
  isa => TrimmedSingleLine,
  required => 1,
);

sub issue_refund {
  Moonpig::X->throw("CreditCard refund unimplemented");
}

1;

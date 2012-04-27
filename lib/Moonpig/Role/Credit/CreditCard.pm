package Moonpig::Role::Credit::CreditCard;
# ABSTRACT: credit received from credit card
use Moose::Role;

use Moonpig::Types qw(TrimmedNonBlankLine);

use namespace::autoclean;

with 'Moonpig::Role::Credit::Refundable::ViaCustSrv';

sub as_string {
  my ($self) = @_;
  return sprintf 'Credit card transaction <%s>',
    $self->transaction_id;
}

has transaction_id => (
  is  => 'ro',
  isa => TrimmedNonBlankLine,
  coerce   => 1,
  required => 1,
);

1;

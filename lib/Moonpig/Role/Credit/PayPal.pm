package Moonpig::Role::Credit::PayPal;
# ABSTRACT: credit received from PayPal
use Moose::Role;

use Moonpig::Types qw(TrimmedSingleLine);

use namespace::autoclean;

with 'Moonpig::Role::Credit';

sub as_string {
  my ($self) = @_;
  return sprintf 'PayPal payment <%s> from %s',
    $self->check_number,
    $self->bank_name;
}

has transaction_id => (
  is  => 'ro',
  isa => TrimmedSingleLine,
  required => 1,
);

has from_name => (
  is  => 'ro',
  isa => TrimmedSingleLine,
);

has from_address => (
  is  => 'ro',
  isa => TrimmedSingleLine,
  required => 1,
);

1;

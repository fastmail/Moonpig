package Moonpig::Role::Credit::PayPal;
# ABSTRACT: credit received from PayPal
use Moose::Role;

use Moonpig::Types qw(TrimmedNonBlankLine);

use namespace::autoclean;

with 'Moonpig::Role::Credit::Refundable::ViaCustSrv';

sub as_string {
  my ($self) = @_;
  return sprintf 'PayPal payment <%s> from %s',
    $self->transaction_id,
    $self->bank_name;
}

has transaction_id => (
  is  => 'ro',
  isa => TrimmedNonBlankLine,
  coerce   => 1,
  required => 1,
);

has from_name => (
  is  => 'ro',
  isa => TrimmedNonBlankLine,
  coerce   => 1,
);

has from_address => (
  is  => 'ro',
  isa => TrimmedNonBlankLine,
  coerce   => 1,
  required => 1,
);

use Moonpig::Behavior::Packable;
PARTIAL_PACK {
  my ($self) = @_;

  return {
    transaction_id => $self->transaction_id,
    from_name      => $self->from_name,
    from_address   => $self->from_address,
  };
};

1;

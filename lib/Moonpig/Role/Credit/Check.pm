package Moonpig::Role::Credit::Check;
# ABSTRACT: credit received by check
use Moose::Role;

use namespace::autoclean;

with 'Moonpig::Role::Credit::Refundable::ViaCustSrv';

sub as_string {
  my ($self) = @_;
  return sprintf 'check no. %s from bank %s',
    $self->check_number,
    $self->bank_name;
}

has check_number => (
  is  => 'ro',
  isa => 'Int',
  required => 1,
);

has bank_name => (
  is  => 'ro',
  isa => 'Str',
  required => 1,
);

use Moonpig::Behavior::Packable;
PARTIAL_PACK {
  my ($self) = @_;

  return {
    check_number => $self->check_number,
    bank_name    => $self->bank_name,
  };
};

1;

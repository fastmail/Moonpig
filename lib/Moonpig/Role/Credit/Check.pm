package Moonpig::Role::Credit::Check;
# ABSTRACT: credit received by check
use Moose::Role;

use namespace::autoclean;

with 'Moonpig::Role::Credit';

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

1;

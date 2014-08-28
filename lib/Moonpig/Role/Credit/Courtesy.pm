package Moonpig::Role::Credit::Courtesy;
# ABSTRACT: credit added by staff for a specific reason

use Moose::Role;

use namespace::autoclean;

with 'Moonpig::Role::Credit';

sub as_string { 'complimentary credit' }

has reason => (
  is   => 'ro',
  isa  => 'Str',
  required => 1,
);

use Moonpig::Behavior::Packable;
PARTIAL_PACK {
  my ($self) = @_;

  return {
    reason => $self->reason,
  };
};

1;

package Moonpig::Role::Contact;
# ABSTRACT: a human you can contact with ledger communications
use Moose::Role;

use Moonpig::Types qw(EmailAddresses TrimmedSingleLine);
use Moose::Util::TypeConstraints;
use MooseX::Types::Moose qw(ArrayRef);

use Moonpig::Behavior::Packable;

use Moonpig::Logger '$Logger';

with(
  'Moonpig::Role::HasGuid',
  'Moonpig::Role::StubBuild',
);

use namespace::autoclean;

# TODO: make this structured, etc, later; also add mailing address.
# -- rjbs, 2010-10-12
has name => (
  is  => 'ro',
  isa => 'Str',
  required => 1,
);

has address_lines => (
  isa => subtype(
    as ArrayRef[ TrimmedSingleLine ],
    where { @$_ > 0 and @$_ <= 2 }
  ),
  traits   => [ 'Array' ],
  handles  => {
    address_lines => 'elements',
  },
  required => 1,
);

has [ qw(city country) ] => (
  is  => 'ro',
  isa => TrimmedSingleLine,
  required => 1,
);

has [ qw(state postal_code) ] => (
  is  => 'ro',
  isa => TrimmedSingleLine,
);

has email_addresses => (
  isa => EmailAddresses,
  traits   => [ 'Array' ],
  handles  => {
    email_addresses => 'elements',
  },
  required => 1,
);

PARTIAL_PACK {
  my ($self) = @_;

  return {
    name        => $self->name,
    address     => [ $self->address_lines ],
    city        => $self->city,
    state       => $self->state,
    country     => $self->country,
    postal_code => $self->postal_code,
    email       => [ $self->email_addresses ],
  };
};

1;

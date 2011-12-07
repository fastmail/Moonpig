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

has first_name => (
  is  => 'ro',
  isa => TrimmedSingleLine,
  required => 1,
);

has last_name => (
  is  => 'ro',
  isa => TrimmedSingleLine,
  required => 1,
);

has organization => (
  is  => 'ro',
  isa => TrimmedSingleLine,
);

# XXX: I hate phone number fields, but we'll need to do a conversion to
# structured phone data later, since we need to import all our unstructured
# phone numbers first. -- rjbs, 2011-11-22
has phone_number => (
  is  => 'ro',
  isa => TrimmedSingleLine,
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
    first_name   => $self->first_name,
    last_name    => $self->last_name,
    organization => $self->organization,
    phone_number => $self->phone_number,
    address      => [ $self->address_lines ],
    city         => $self->city,
    state        => $self->state,
    country      => $self->country,
    postal_code  => $self->postal_code,
    email        => [ $self->email_addresses ],
  };
};

1;

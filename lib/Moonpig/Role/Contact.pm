package Moonpig::Role::Contact;
# ABSTRACT: a human you can contact with ledger communications

use Moose::Role;

use Moonpig::Types qw(EmailAddresses TrimmedSingleLine);
use Moose::Util::TypeConstraints;
use MooseX::Types::Moose qw(ArrayRef HashRef);

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
  coerce   => 1,
  required => 1,
);

has last_name => (
  is  => 'ro',
  isa => TrimmedSingleLine,
  coerce   => 1,
  required => 1,
);

has organization => (
  is  => 'ro',
  isa => TrimmedSingleLine,
  coerce    => 1,
  predicate => 'has_organization',
);

# XXX: I hate phone number fields, but we'll need to do a conversion to
# structured phone data later, since we need to import all our unstructured
# phone numbers first. -- rjbs, 2011-11-22
has phone_book => (
  is  => 'ro',
  isa => subtype(
    as HashRef[ TrimmedSingleLine ],
    where { keys %$_ > 0 }
  ),
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
  coerce   => 1,
  required => 1,
);

has state => (
  is  => 'ro',
  isa => TrimmedSingleLine,
  coerce    => 1,
  predicate => 'has_state',
);

has postal_code => (
  is  => 'ro',
  isa => TrimmedSingleLine,
  coerce    => 1,
  predicate => 'has_postal_code',
);

has twitter_id => (
  is  => 'ro',
  isa => subtype(
    as TrimmedSingleLine,
    where { ! /[^0-9]/ }
  ),
  predicate => 'has_twitter_id',
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
    phone_book   => $self->phone_book,
    address      => [ $self->address_lines ], # deprecate -- rjbs, 2012-04-25
    address_lines=> [ $self->address_lines ],
    city         => $self->city,
    state        => $self->state,
    country      => $self->country,
    postal_code  => $self->postal_code,
    email        => [ $self->email_addresses ], # deprecate -- rjbs, 2012-04-25
    email_addresses => [ $self->email_addresses ],
    twitter_id   => $self->twitter_id,
  };
};

1;

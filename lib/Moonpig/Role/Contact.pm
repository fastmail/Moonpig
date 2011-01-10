package Moonpig::Role::Contact;
# ABSTRACT: a human you can contact with ledger communications
use Moose::Role;

use Moonpig::Types qw(EmailAddresses);
use MooseX::Types::Moose qw(ArrayRef);

use Moonpig::Logger '$Logger';

with(
  'Moonpig::Role::HasGuid',
  'Moonpig::Role::StubBuild',
);

use namespace::autoclean;

# TODO: make this structured, etc, later; also add mailing address.
# -- rjbs, 2010-10-12
has name => (
  is  => 'rw',
  isa => 'Str',
  required => 1,
);

has email_addresses => (
  isa => EmailAddresses,
  traits   => [ 'Array' ],
  handles  => {
    email_addresses => 'elements',
  },
  required => 1,
);

after BUILD => sub {
  my ($self) = @_;
  $Logger->log([
    'created new contact %s (%s)',
    $self->guid,
    $self->meta->name,
  ]);
};

1;

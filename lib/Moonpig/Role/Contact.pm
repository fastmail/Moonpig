package Moonpig::Role::Contact;
use Moose::Role;

use Moonpig::Types qw(EmailAddresses);
use MooseX::Types::Moose qw(ArrayRef);

use namespace::autoclean;

# TODO: make this structured, etc, later; also add mailing address.
# -- rjbs, 2010-10-12
has name => (
  is  => 'rw',
  isa => 'Str',
  required => 1,
);

has email_addresses => (
  is  => 'ro',
  isa => EmailAddresses,
  required => 1,
);

1;

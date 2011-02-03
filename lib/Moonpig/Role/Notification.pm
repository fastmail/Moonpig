package Moonpig::Role::Notification;
# ABSTRACT: something that can happen, like an exception or event
use Moose::Role;

use namespace::autoclean;

with(
  'Role::Identifiable::HasIdent',
  'Role::Identifiable::HasTags',

  'Role::HasPayload::Merged',

  'Role::HasMessage::Errf' => {
    default  => sub { $_[0]->ident },
    lazy     => 1,
  },

  'MooseX::OneArgNew' => {
    type     => 'Str',
    init_arg => 'ident',
  },
);

1;

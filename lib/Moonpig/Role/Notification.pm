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

around BUILDARGS => sub {
  my ($orig, $self, @args) = @_;
  return $self->$orig(@args) if @args < 2 || ref $args[0];
  my $ident = shift @args;
  my $payload = @args == 1 ? $args[0] : { @args };
  return { ident => $ident, payload => $payload };
};

1;

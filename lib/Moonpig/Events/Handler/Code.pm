package Moonpig::Events::Handler::Code;
# ABSTRACT: an event handler that just calls a coderef
use Moose;
with 'Moonpig::Role::EventHandler';

use MooseX::Types::Moose qw(CodeRef);

use namespace::autoclean;

has code => (
  is  => 'ro',
  isa => CodeRef,
  required => 1,
);

sub handle_event {
  my ($self, $event, $receiver, $arg) = @_;

  my $code = $self->code;
  $code->($receiver, $event, $arg, $self);
}

1;

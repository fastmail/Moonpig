package Moonpig::Events::Handler::Code;
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
  $code->($self, $event, $receiver, $arg);
}

1;

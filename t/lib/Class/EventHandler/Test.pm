package t::lib::Class::EventHandler::Test;
# ABSTRACT: an event handler that accumulates a log of each time it is invoked
use Moose;
with 'Moonpig::Role::EventHandler';

use MooseX::StrictConstructor;

use namespace::autoclean;

has log => (
  isa => 'ArrayRef',
  default  => sub {  []  },
  traits   => [ 'Array' ],
  handles  => {
    clear_log   => 'clear',
    record_call => 'push',
    calls       => 'elements',
    call        => 'get',
  },
);

sub handle_event {
  my ($self, $event, $receiver, $arg) = @_;

  $self->record_call([ $receiver, $event, $arg ]);
}

1;

package t::lib::Class::EventHandler::Test;
use Moose;
extends 'Moonpig::Events::Handler::Code';

has calls => (
  isa => 'ArrayRef',
  init_arg => undef,
  default  => sub {  []  },
  traits   => [ 'Array' ],
  handles  => {
    clear_calls => 'clear',
    record_call => 'push',
    calls       => 'elements',
    call        => 'get',
  },
);

has '+code' => (
  default => sub {
    return sub {
      my ($receiver, $event, $arg, $self) = @_;

      $self->record_call([ $receiver, $event, $arg ]);
    };
  },
);

1;

package Moonpig::Events::Handler::Missing;
# ABSTRACT: an event handler that throws a "handler missing" exception

use Moose;
with 'Moonpig::Role::EventHandler';

use MooseX::StrictConstructor;

use Moonpig::X;

use namespace::autoclean;

sub handle_event {
  my ($self, $event, $receiver, $arg) = @_;

  Moonpig::X->throw({
    ident => "event received by Missing handler",
    payload => {
      event_ident => $event->ident,
      receiver    => $receiver,
    },
  });
}

1;

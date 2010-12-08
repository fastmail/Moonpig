package Moonpig::Env::Test;
use Moose;
with 'Moonpig::Role::Env';

Moonpig->set_env( __PACKAGE__->new );

use Email::Sender::Transport::Test;
use Moonpig::Events::Handler::Code;

has email_sender => (
  is   => 'ro',
  does => 'Email::Sender::Transport',
  default => sub { Email::Sender::Transport::Test->new },
);

sub handle_send_email {
  my ($self, $event, $arg) = @_;

  # XXX: validate email -- rjbs, 2010-12-08

  $self->email_sender->send_email($arg->{email}, $arg->{env});
}

1;
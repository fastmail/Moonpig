package Moonpig::Env::Normal;
use Moonpig::DateTime;
use Moose;
use Carp qw(confess);
with 'Moonpig::Role::Env';

Moonpig->set_env( __PACKAGE__->new );

sub handle_send_email {
  my ($self, $event, $arg) = @_;

  confess "unimplemented";
}

sub now {
  return Moonpig::DateTime->now();
}

1;

package Moonpig::Env::Normal;
# ABSTRACT: a standard, production environment for Moonpig
use Moose;

use Moonpig::DateTime;
use Carp qw(confess);
with 'Moonpig::Role::Env';

use namespace::autoclean;

Moonpig->set_env( __PACKAGE__->new );

sub handle_send_email {
  my ($self, $event, $arg) = @_;

  confess "unimplemented";
}

sub now {
  return Moonpig::DateTime->now();
}

1;

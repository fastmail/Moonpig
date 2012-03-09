package Moonpig::Env::Normal;
# ABSTRACT: a standard, production environment for Moonpig
use Moose;
use MooseX::StrictConstructor;

use Moonpig::DateTime;
use Carp qw(confess);
with 'Moonpig::Role::Env';

use namespace::autoclean;

sub extra_share_roots {}

sub default_from_email_address {
  confess "unimplemented";
}

sub handle_queue_email {
  my ($self, $event, $arg) = @_;

  confess "unimplemented";
}

sub send_email {
  confess "unimplemented";
}

sub file_customer_service_request {
  confess "unimplemented";
}

sub storage_class {
  require Moonpig::Storage::Spike;
  'Moonpig::Storage::Spike';
}

sub storage_init_args { return }

sub now {
  return Moonpig::DateTime->now();
}

sub register_object {
  # do nothing
}

1;

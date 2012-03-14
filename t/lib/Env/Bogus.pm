package t::lib::Env::Bogus;
# ABSTRACT: bogus env; composes, doesn't work
use Moose;
use MooseX::StrictConstructor;

use Moonpig::DateTime;
use Carp qw(confess);
with 'Moonpig::Role::Env';

use namespace::autoclean;

sub extra_share_roots {}
sub register_object   {}

# EmailSender

sub default_from_email_address { confess "unimplemented" }
sub handle_queue_email         { confess "unimplemented" }
sub send_email                 { confess "unimplemented" }

# reports and requests
sub file_customer_service_request { confess "unimplemented" }
sub report_exception              { confess "unimplemented" }

# storage
sub storage_class {
  require Moonpig::Storage::Spike;
  'Moonpig::Storage::Spike';
}

sub storage_init_args { return }

# time / clock
sub now { return Moonpig::DateTime->now() }

1;

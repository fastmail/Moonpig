package Moonpig::Role::Env::CustSrvEmail;
# ABSTRACT: an environment that sends cust srv. requests via email

use Moose::Role;
with qw(Moonpig::Role::Env Moonpig::Role::Env::EmailSender);

use Moonpig::Types qw(Ledger);
use Stick::Util qw(ppack);

use namespace::autoclean;

requires 'customer_service_from_email_address';
requires 'customer_service_to_email_address';
requires 'customer_service_mkit_name';

sub file_customer_service_request {
  my ($self, $ledger, $payload) = @_;

  Ledger->assert_valid($ledger);

  my $email = Moonpig->env->mkits->assemble_kit(
    $self->customer_service_mkit_name,
    {
      to_addresses => [ $self->customer_service_to_email_address->as_string ],
      subject => 'Customer Service Request',
      payload => $payload,
      ledger  => $ledger,
    },
  );

  my $env = {
    to   => [ $self->customer_service_to_email_address->address ],
    from => $self->customer_service_from_email_address->address,
  };

  $ledger->queue_email($email, $env);
}

1;

package Moonpig::Role::Env::CustSrvEmail;
# ABSTRACT: an environment that send cust srv. requests via email

use Moose::Role;
with 'Moonpig::Role::Env';

use Stick::Util qw(ppack);

use namespace::autoclean;

requires 'customer_service_from_email_address';
requires 'customer_service_to_email_address';
requires 'customer_service_mkit_name';

sub file_customer_service_request {
  my ($self, $ledger, $arg) = @_;

  my $email = Moonpig->env->mkits->assemble_kit(
    $self->customer_service_mkit_name,
    {
      to_addresses => [ $self->customer_service_to_email_address->address ],
      subject => 'Customer Service Request',
      arg     =>  $arg,
    },
  );

  $ledger->queue_email(
    $email,
    {
      to   => $self->customer_service_to_email_address,
      from => $self->customer_service_from_email_address,
    },
  );
}

1;

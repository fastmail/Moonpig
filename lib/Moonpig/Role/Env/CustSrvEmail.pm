package Moonpig::Role::Env::CustSrvEmail;
# ABSTRACT: an environment that send cust srv. requests via email

use Moose::Role;
with 'Moonpig::Role::Env';

use Moonpig::Types qw(Ledger);
use Stick::Util qw(ppack);

use namespace::autoclean;

requires 'customer_service_from_email_address';
requires 'customer_service_to_email_address';
requires 'customer_service_mkit_name';

sub __cust_srv_email {
  my ($self, $ledger, $payload) = @_;

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

  return ($email, $env);
}

sub file_customer_service_request {
  my ($self, $ledger, $payload) = @_;

  Ledger->assert_valid($ledger);
  my ($email, $env) = $self->__cust_srv_email($ledger, $payload);

  $ledger->queue_email($email, $env);
}

sub file_customer_service_error_report {
  my ($self, $maybe_ledger, $payload) = @_;
  defined $maybe_ledger && Ledger->assert_valid($maybe_ledger);

  my ($email, $env) = $self->__cust_srv_email($maybe_ledger, $payload);
  $self->send_email($email, $env);
}

1;

package Moonpig::Role::Env::CustSrvEmail;
# ABSTRACT: an environment that send cust srv. requests via email

use Moose::Role;
with 'Moonpig::Role::Env';

use Stick::Util qw(ppack);

use namespace::autoclean;

sub file_customer_service_request {
  my ($self, $ledger, $arg) = @_;

  my $email = Moonpig->env->mkits->assemble_kit(
    'generic',
    {
      to_addresses => [ $self->default_from_email_address ],
      subject => 'Customer Service Request',
      body    => JSON->new->ascii->encode( ppack($arg) ),
    },
  );

  $ledger->queue_email(
    $email,
    {
      to   => $self->default_from_email_address,
      from => $self->default_from_email_address,
    },
  );
}

1;

package Moonpig::Role::Credit::Refundable::ViaCustSrv;
use Moose::Role;
# ABSTRACT: a refund that gets back to the payer via customer service

use Stick::Util qw(ppack);

with(
  'Moonpig::Role::Credit::Refundable',
);

sub issue_refund {
  my ($self) = @_;

  Moonpig->env->file_customer_service_request(
    $self->ledger,
    {
      request => "issue refund",
      credit  => ppack($self),
    },
  );
}

1;

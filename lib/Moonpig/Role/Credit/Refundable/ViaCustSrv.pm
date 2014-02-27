package Moonpig::Role::Credit::Refundable::ViaCustSrv;
# ABSTRACT: a refund that gets back to the payer via customer service

use Moose::Role;

use Stick::Util qw(ppack);

with(
  'Moonpig::Role::Credit::Refundable',
);

sub issue_refund {
  my ($self, $amount) = @_;

  Moonpig->env->file_customer_service_request(
    $self->ledger,
    {
      request => "issue refund",
      amount  => $amount,
      credit  => ppack($self),
    },
  );
}

1;

package t::lib::Role::Refundable::Test;
use Moose::Role;

use Moonpig::Logger '$Logger';
use Moonpig::Util qw(class);
use Stick::Util qw(ppack);

with(
  'Moonpig::Role::Credit::Refundable',
);

sub issue_refund {
  my ($self) = @_;

  $Logger->log("REFUND ISSUED");
  Moonpig->env->file_customer_service_request(
    $self->ledger,
    {
      request => "issue refund",
      credit  => ppack($self),
    },
  );
}

1;

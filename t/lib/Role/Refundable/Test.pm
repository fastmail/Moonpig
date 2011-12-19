package t::lib::Role::Refundable::Test;
use Moose::Role;

use Moonpig::Logger '$Logger';
use Moonpig::Util qw(class);

with(
  'Moonpig::Role::Credit::Refundable',
);

sub issue_refund {
  my ($self) = @_;

  $Logger->log("REFUND ISSUED");

  my $refund = $self->ledger->add_refund(
    class(qw(Refund)),
    {
      ledger => $self->ledger,
    },
  );

  $self->ledger->create_transfer({
    type  => 'refund',
    from  => $self,
    to    => $refund,
    amount  => $self->amount,
  });

  return $refund;
}

1;

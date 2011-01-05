package t::lib::Role::Refundable::Test;
use Moose::Role;

use Moonpig::CreditApplication;
use Moonpig::Logger '$Logger';
use Moonpig::Util qw(class);

with(
  'Moonpig::Role::Refundable',
);

sub issue_refund {
  my ($self, $__temp__ledger) = @_;

  $Logger->log("REFUND ISSUED");

  my $refund = class(qw(Refund))->new({
    ledger => $__temp__ledger,
  });

  Moonpig::CreditApplication->new({
    credit  => $self,
    payable => $refund,
    amount  => $self->amount,
  });
}

1;

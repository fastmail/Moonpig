
package Moonpig::Role::Credit::Refundable::ViaPinstripe;
# ABSTRACT: a refund that gets back to the payer via pinstripe

use Moose::Role;
use Stick::Util qw(ppack);

with(
  'Moonpig::Role::Credit::Refundable',
);

sub issue_refund {
  my ($self, $amount) = @_;

  my ($processor, $token_id) = split /:/, $self->transaction_id;
  my $amount_cents = int $amount/1000;

  $self->ledger->queue_job('moonpig.pinstripe.issue-refund', {
    processor => $processor,
    token_id  => $token_id,
    amount_cents => $amount_cents
  });
}

1;

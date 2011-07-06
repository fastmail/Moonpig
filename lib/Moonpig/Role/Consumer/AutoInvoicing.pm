package Moonpig::Role::Consumer::AutoInvoicing;

use Moose::Role;

use List::MoreUtils qw(natatime);

use Moonpig::DateTime;
use Moonpig::Events::Handler::Method;
use Moonpig::Logger '$Logger';
use Moonpig::Util qw(class);

with(
  'Moonpig::Role::Consumer',
  'Moonpig::Role::Consumer::ChargesBank', # for charge_tags
);

use Moonpig::Behavior::EventHandlers;

implicit_event_handlers {
  return {
    created => {
      'initial-invoice' => Moonpig::Events::Handler::Method->new(
        method_name => '_invoice',
      ),
    },
  };
};

# For any given date, what do we think the total costs of ownership for this
# consumer are?  Example:
# [ 'basic account' => dollars(50), 'allmail' => dollars(20), 'support' => .. ]
# This is an arrayref so we can have ordered line items for display.
requires 'costs_on';

sub _invoice {
  my ($self) = @_;

  my $invoice = $self->ledger->current_invoice;

  my @costs = $self->costs_on( Moonpig->env->now );

  my $iter = natatime 2, @costs;

  while (my ($desc, $amt) = $iter->()) {
    $invoice->add_charge(
      class( "InvoiceCharge::Bankable" )->new({
        description => $desc,
        amount      => $amt,
        tags        => $self->charge_tags,
        consumer    => $self,
      }),
    );
  }
}

1;

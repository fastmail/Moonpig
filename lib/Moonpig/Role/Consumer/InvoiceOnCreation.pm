package Moonpig::Role::Consumer::InvoiceOnCreation;

use Moose::Role;

use List::MoreUtils qw(natatime);

use Moonpig::DateTime;
use Moonpig::Events::Handler::Method;
use Moonpig::Logger '$Logger';
use Moonpig::Util qw(class);
use MooseX::Types::Moose qw(ArrayRef);

with(
  'Moonpig::Role::Consumer',
);

use Moonpig::Behavior::EventHandlers;

requires 'invoice_costs';

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

  my @costs = $self->invoice_costs();

  my $iter = natatime 2, @costs;

  while (my ($desc, $amt) = $iter->()) {
    $invoice->add_charge(
      $self->build_charge({
        description => $desc,
        amount      => $amt,
        tags        => $self->invoice_charge_tags,
        consumer    => $self,
      }),
    );
  }

  # XXX: magic charges go here, but this protocol needs to be clarified and
  # un-underscored -- rjbs, 2011-08-18
  if ($self->can('_extra_invoice_charges')) {
    for my $charge ($self->_extra_invoice_charges) {
      $invoice->add_charge( $charge );
    }
  }
}

1;

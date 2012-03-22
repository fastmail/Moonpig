package Moonpig::Role::Consumer::InvoiceOnCreation;
use Moose::Role;
# ABSTRACT: a consumer that charges the invoice when it's created

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

requires 'initial_invoice_charge_pairs';

implicit_event_handlers {
  return {
    created => {
      'initial-invoice' => Moonpig::Events::Handler::Method->new(
        method_name => '_invoice',
      ),
    },
  };
};

sub _invoice {
  my ($self) = @_;

  my $invoice = $self->ledger->current_invoice;

  my @charge_pairs = $self->initial_invoice_charge_pairs;

  my $iter = natatime 2, @charge_pairs;

  while (my ($desc, $amt) = $iter->()) {
    $self->charge_invoice($invoice, { description => $desc, amount => $amt });
  }
}

1;

package Moonpig::Role::Consumer::InvoiceOnCreation;
use Moose::Role;
# ABSTRACT: a consumer that charges the invoice when it's created

use Moonpig::DateTime;
use Moonpig::Events::Handler::Method;
use Moonpig::Logger '$Logger';
use Moonpig::Util qw(class);
use MooseX::Types::Moose qw(ArrayRef);

use Stick::Publisher;
use Stick::Publisher::Publish;

with(
  'Moonpig::Role::Consumer',
);

use Moonpig::Behavior::EventHandlers;

requires 'initial_invoice_charge_structs';

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

  for my $struct ($self->initial_invoice_charge_structs) {
    $self->charge_invoice($invoice, {
      description => $struct->{description},
      amount      => $struct->{amount},
    });
  }
}

publish reinvoice_initial_charges => {
  -path => 'reinvoice-initial-charges',
  -http_method => 'post',
} => sub {
  my ($self) = @_;

  Moonpig::X->throw("cannot reinvoice after funding")
    if $self->was_ever_funded;

  $self->abandon_all_unpaid_charges;
  $self->_invoice;
  if ($self->has_replacement) {
    $self->replacement->reinvoice_initial_charges;
  }

  return $self;
};

1;

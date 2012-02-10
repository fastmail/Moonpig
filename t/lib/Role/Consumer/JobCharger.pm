package t::lib::Role::Consumer::JobCharger;
use Moose::Role;

use Moonpig::Util qw(class dollars);

use namespace::autoclean;

with(
  'Moonpig::Role::Consumer',
  'Moonpig::Role::Consumer::InvoiceOnCreation',
);

sub initial_invoice_charge_pairs {
  return ('basic payment' => dollars(1));
}

around _invoice => sub {
  my ($orig, $self) = @_;

  $self->$orig;

  my $invoice = $self->ledger->current_invoice;

  my $class = class( qw(
    InvoiceCharge
    =t::lib::Role::InvoiceCharge::JobCreator
  ) );

  my $charge = $class->new({
    description => 'magic charge',
    amount      => dollars(2),
    tags        => [ ],
    consumer    => $self,
  });

  $invoice->add_charge( $charge );
};

1;

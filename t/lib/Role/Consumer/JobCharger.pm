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

sub _extra_invoice_charges {
  my ($self) = @_;

  my $class = class( qw(
    InvoiceCharge
    =t::lib::Role::InvoiceCharge::JobCreator
  ) );

  my $charge = $class->new({
    description => 'magic charge',
    amount      => dollars(2),
    tags        => [ ],
    consumer    => $self,
  }),
}

1;

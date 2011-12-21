package t::lib::Role::Consumer::JobCharger;
use Moose::Role;

use Moonpig::Util qw(class dollars);

use namespace::autoclean;

with(
  'Moonpig::Role::Consumer',
  # 'Moonpig::Role::Consumer::FixedCost',
  'Moonpig::Role::Consumer::InvoiceOnCreation',
);

sub initial_invoice_costs {
  return ('basic payment' => dollars(1));
}

# Does not vary with time
sub costs_on {
  $_[0]->initial_invoice_costs;
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

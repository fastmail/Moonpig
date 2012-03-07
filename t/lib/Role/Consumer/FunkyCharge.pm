package t::lib::Role::Consumer::FunkyCharge;
use Moose::Role;
use Moonpig::Util qw(class dollars);
use Moonpig::Types qw(Factory);
use MooseX::Types::Moose qw(ArrayRef);

has charge_roles => (
  is => 'ro',
  isa => ArrayRef [ Factory ],
  required => 1,
);

with(
  'Moonpig::Role::Consumer',
  'Moonpig::Role::Consumer::InvoiceOnCreation',
);

sub initial_invoice_charge_pairs {
  return ('basic payment' => dollars(1));
}

sub build_invoice_charge {
  my ($self, $args) = @_;
  return class(@{$self->charge_roles})->new($args);
}

1;

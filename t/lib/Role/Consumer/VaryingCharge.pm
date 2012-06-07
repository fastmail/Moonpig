package t::lib::Role::Consumer::VaryingCharge;
use Moose::Role;
use Moonpig::Util qw(class dollars);
use Moonpig::Types qw(Factory  NonNegativeMillicents);
use MooseX::Types::Moose qw(ArrayRef);

has total_charge_amount => (
  is => 'rw',
  isa => NonNegativeMillicents,
  required => 1,
);

with(
  'Moonpig::Role::Consumer::ByTime',
);

around initial_invoice_charge_pairs => sub {
  my ($orig, $self, @args) = @_;
  return $self->charge_pairs_on();
};

sub charge_pairs_on {
  return ('charge' => $_[0]->total_charge_amount);
}

1;

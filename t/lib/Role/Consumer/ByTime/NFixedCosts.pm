package t::lib::Role::Consumer::ByTime::NFixedCosts;
use Moose::Role;

use Moonpig;
use Moonpig::Logger '$Logger';
use Moonpig::Trait::Copy;
use Moonpig::Types qw(PositiveMillicents);
use MooseX::Types::Moose qw(ArrayRef);

use namespace::autoclean;

has cost_amounts => (
  is  => 'ro',
  isa => ArrayRef[ PositiveMillicents ],
  required => 1,
  traits   => [ qw(Copy) ],
);

sub invoice_costs {
  my ($self) = @_;
  my @charges = map {; ($self->charge_description, $_) }
                @{ $self->cost_amounts };

  return @charges;
}

# Does not vary with time
sub costs_on {
  return $_[0]->invoice_costs;
}

# Description for charge.  You will probably want to override this method
has charge_description => (
  is => 'ro',
  isa => 'Str',
  required => 1,
  traits => [ qw(Copy) ],
);

with(
  'Moonpig::Role::Consumer::ByTime',
);

1;

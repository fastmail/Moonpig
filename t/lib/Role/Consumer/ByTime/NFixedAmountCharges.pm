package t::lib::Role::Consumer::ByTime::NFixedAmountCharges;
use Moose::Role;

use Moonpig;
use Moonpig::Logger '$Logger';
use Moonpig::Trait::Copy;
use Moonpig::Types qw(PositiveMillicents);
use MooseX::Types::Moose qw(ArrayRef);

use namespace::autoclean;

has charge_amounts => (
  is  => 'ro',
  isa => ArrayRef[ PositiveMillicents ],
  required => 1,
  traits   => [ qw(Copy) ],
);

# Does not vary with time
sub charge_structs_on {
  my ($self) = @_;
  my @structs = map {; {
    description => $self->charge_description,
    amount      => $_,
  } } @{ $self->charge_amounts };
  return @structs;
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

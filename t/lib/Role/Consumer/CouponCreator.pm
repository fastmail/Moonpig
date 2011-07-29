package t::lib::Role::Charge::CouponCreator;
use Moose::Role;

use Moonpig;
use Moonpig::Logger '$Logger';
use Moonpig::Trait::Copy;
use Moonpig::Types qw(Factory);
use MooseX::Types::Moose qw(HashRef);

use namespace::autoclean;

with(
  'Moonpig::Role::InvoiceCharge',
  'Moonpig::Role::Charge::HandlesEvents',
);

implicit_event_handlers {
  return { paid => { add_coupon => Moonpig::Events::Handler::Method->new("add_coupon") } };
};

has coupon_factory => (
  is  => 'ro',
  isa => Factory,
  required => 1,
  traits   => [ qw(Copy) ],
);

has coupon_args => (
  is => 'ro',
  isa => HashRef,
  default => sub { {} },
  traits   => [ qw(Copy) ],
);

sub add_coupon {
  my ($self, $event) = @_;
}

1;

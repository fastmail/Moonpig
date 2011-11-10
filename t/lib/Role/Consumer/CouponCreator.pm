package t::lib::Role::Consumer::CouponCreator;
use Moose::Role;

use Moonpig;
use Moonpig::Logger '$Logger';
use Moonpig::Trait::Copy;
use Moonpig::Types qw(Factory);
use Moonpig::Util qw(class);
use MooseX::Types::Moose qw(HashRef);

use namespace::autoclean;

has coupon_class => (
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

after _invoice => sub {
  my ($self) = @_;
  $self->ledger->current_invoice->add_charge(
    class("InvoiceCharge::CouponCreator")->new({
      consumer => $self,
      coupon_class => $self->coupon_class,
      coupon_args => $self->coupon_args,
      description => "Pseudocharge to trigger coupon creation on behalf of consumer for " .
        $self->xid,
      amount => 1,
      tags => [ $self->xid ],
    }));
};


1;

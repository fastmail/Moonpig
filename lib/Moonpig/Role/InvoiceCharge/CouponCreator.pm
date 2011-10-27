package Moonpig::Role::InvoiceCharge::CouponCreator;
# ABSTRACT: a charge that, when paid, should have a bank created for the paid amount
use Moose::Role;

with(
  'Moonpig::Role::InvoiceCharge::Active',
);

use Moonpig;
use Moonpig::Logger '$Logger';
use Moonpig::Types qw(Factory GUID Ledger);
use Moonpig::Util qw(class);
use MooseX::Types::Moose qw(HashRef);

use namespace::autoclean;

has coupon_class => (
  is => 'ro',
  isa => Factory,
  required => 1,
);

has coupon_args => (
  is => 'ro',
  isa => HashRef,
  default => sub { {} },
);

sub when_paid {
  # Create the coupon
  my ($self, $event) = @_;

  my $coupon;
  Moonpig->env->storage->do_rw(
    sub {
      $coupon = $self->ledger->add_coupon($self->coupon_class, $self->coupon_args);
      $Logger->log([ 'created coupon %s in ledger %s', $coupon->ident, $self->ledger->ident ]);
      Moonpig->env->storage->save_ledger($self->ledger);
    });
  return $coupon;
}

1;

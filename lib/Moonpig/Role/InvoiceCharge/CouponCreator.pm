package Moonpig::Role::InvoiceCharge::CouponCreator;
# ABSTRACT: a charge that, when paid, should have a bank created for the paid amount
use Moose::Role;

with(
  'Moonpig::Role::InvoiceCharge',
);

use Moonpig;
use Moonpig::Logger '$Logger';
use Moonpig::Types qw(Factory GUID Ledger);
use Moonpig::Util qw(class);
use MooseX::Types::Moose qw(HashRef);

use namespace::autoclean;
use Moonpig::Behavior::EventHandlers;
use Moonpig::Events::Handler::Method;

implicit_event_handlers {
  return {
    'paid' => {
      'create_coupon' => Moonpig::Events::Handler::Method->new('create_coupon'),
    },
  }
};

# Do we really need this? Is there no other way to find the ledger?
has ledger => (
  is => 'ro',
  isa => Ledger,
  required => 1,
  weak_ref => 1,
);

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

sub create_coupon {
  my ($self, $event) = @_;

  my $coupon;
  Moonpig->env->storage->do_rw(
    sub {
      $coupon = $self->ledger->add_coupon($self->coupon_class, $self->coupon_args);
      $Logger->log([ 'created coupon %s in ledger %s', $coupon->ident, $self->ledger->ident ]);
    });
  return $coupon;
}

1;

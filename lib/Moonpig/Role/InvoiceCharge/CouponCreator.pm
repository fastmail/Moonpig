package Moonpig::Role::InvoiceCharge::CouponCreator;
# ABSTRACT: a charge that, when paid, should have a bank created for the paid amount
use Moose::Role;

with(
  'Moonpig::Role::InvoiceCharge',
);

use Moonpig;
use Moonpig::Logger '$Logger';
use Moonpig::Types qw(Factory GUID);
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
has ledger_guid => (
  is => 'ro',
  isa => GUID,
  required => 1,
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
      my $ledger = $self->find_ledger__;
      $coupon = $ledger->add_coupon_to_ledger($self->coupon_class, $self->coupon_args);
      $Logger->log([ 'created coupon %s in ledger %s', $coupon->ident, $ledger->ident ]);
    });
  return $coupon;
}

sub find_ledger__ {
  my ($self) = @_;
  return Moonpig->env->storage->retrieve_ledger_for_guid($self->ledger_guid);
}

1;

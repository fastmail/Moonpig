package Moonpig::Role::Consumer::Charges;
# ABSTRACT: a consumer that can issue journal charges
use Moose::Role;
with(
  'Moonpig::Role::Consumer',
);

use Moonpig::Trait::Copy;
use Moonpig::Util qw(class);
use MooseX::Types::Moose qw(ArrayRef);

use Moonpig::Behavior::Packable;

use namespace::autoclean;

has extra_journal_charge_tags => (
  is  => 'ro',
  isa => ArrayRef,
  default => sub { [] },
  traits => [ qw(Copy) ],
);

sub journal_charge_tags {
  my ($self) = @_;
  return [ $self->xid, @{$self->extra_journal_charge_tags} ]
}

sub build_charge {
  my ($self, $args) = @_;
  return class("InvoiceCharge::Bankable")->new($args);
}

PARTIAL_PACK {
  my ($self) = @_;
  return {
    unapplied_amount => $self->unapplied_amount,
  };
};

1;

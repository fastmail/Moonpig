package Moonpig::Role::Consumer::ChargesBank;
# ABSTRACT: a consumer that can issue charges
use Moose::Role;
with(
  'Moonpig::Role::Consumer',
);

use Moonpig::Trait::Copy;
use Moonpig::Types qw(TimeInterval);
use MooseX::Types::Moose qw(ArrayRef);

use namespace::autoclean;

has extra_charge_tags => (
  is  => 'ro',
  isa => ArrayRef,
  default => sub { [] },
  traits => [ qw(Copy) ],
);

sub charge_tags {
  my ($self) = @_;
  return [ $self->xid, @{$self->extra_charge_tags} ]
}

# When the object has less than this long to live, it will
# start posting low-balance events to its successor, or to itself if
# it has no successor
has old_age => (
  is => 'ro',
  required => 1,
  isa => TimeInterval,
  traits => [ qw(Copy) ],
);

has bank => (
  reader => 'bank',
  writer => '_set_bank',
  does   => 'Moonpig::Role::Bank',
  traits => [ qw(SetOnce) ],
  predicate => 'has_bank',
);

before _set_bank => sub {
  my ($self, $bank) = @_;

  unless ($self->ledger->guid eq $bank->ledger->guid) {
    confess sprintf(
      "cannot associate consumer from %s with bank from %s",
      $self->ledger->ident,
      $bank->ledger->ident,
    );
  }
};

sub unapplied_amount {
  my ($self) = @_;
  return $self->has_bank ? $self->bank->unapplied_amount : 0;
}

1;

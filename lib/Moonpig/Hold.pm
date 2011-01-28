package Moonpig::Hold;
# ABSTRACT: a hold on funds, making them unavailable
use Moose;

use Moonpig::Types qw(Millicents);

use Moose::Util::TypeConstraints;

use namespace::autoclean;

with(
  'Moonpig::Role::TransferLike' => {
    from_name => 'bank',
    from_type => role_type('Moonpig::Role::Bank'),

    to_name   => 'consumer',
    to_type   => role_type('Moonpig::Role::Consumer'),

    allow_deletion => 1,
  },
);

has subsidiary_hold => (
  is => 'rw',
  isa => 'Moonpig::Hold',
  predicate => 'has_subsidiary_hold',
);

before delete => sub {
  my ($self) = @_;
  $self->subsidiary_hold->delete if $self->has_subsidiary_hold;
};

sub commit {
  my ($self) = @_;
  $self->consumer->create_charge_for_hold($self);
  $self->subsidiary_hold->commit() if $self->has_subsidiary_hold;
  $self->delete;
}

1;

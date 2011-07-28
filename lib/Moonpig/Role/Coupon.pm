package Moonpig::Role::Coupon;
# ABSTRACT: a discount for paying for a certain service
use Moose::Role;
use Moonpig;
use Moonpig::Types qw(Factory Time TimeInterval);
use Moonpig::Util qw(class);

with(
  'Moonpig::Role::HasGuid',
  'Moonpig::Role::LedgerComponent',
);

use namespace::autoclean;

has description => (
  is => 'ro',
  isa => 'Str',
  required => 1,
);

has lifetime => (
  is => 'ro',
  isa => TimeInterval,
  predicate => 'has_expiration_date',
);

has created_at => (
  is => 'ro',
  isa => Time,
  default => sub { Moonpig->env->now },
  init_arg => undef,
);

sub expiration_date {
  my ($self) = @_;
  return unless $self->has_expiration_date;
  return $self->created_at + $self->lifetime;
}

has credit_class => (
  is => 'ro',
  isa => 'Str',
  default => class('Credit::Discount'),
);

sub is_expired {
  my ($self) = @_;
  $self->has_expiration_date
    and $self->expiration_date->precedes(Moonpig->env->now);
}

requires 'applies_to';
requires 'discount_amount_for';

sub applied { } # No-op

sub applies_to_invoice {
  my ($self, $invoice) = @_;
  return grep $self->applies_to($_), $invoice->all_charges;
}

sub create_discount_for {
  my ($self, $charge) = @_;
  return if $self->is_expired;
  return unless $self->applies_to($charge);

  my $amount = $self->discount_amount_for($charge);
  return if $amount == 0;

  return $self->ledger->add_credit(
    $self->credit_class,
    { amount => $amount });
}

1;

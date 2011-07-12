package Moonpig::Role::Credit;
# ABSTRACT: a ledger's credit toward paying invoices
use Moose::Role;

with(
  'Moonpig::Role::HasGuid',
  'Moonpig::Role::LedgerComponent',
  'Moonpig::Role::CanTransfer' => { transferer_type => "credit" },
);

use Moonpig::Types qw(PositiveMillicents);

use namespace::autoclean;

requires 'as_string'; # to be used on line items

has amount => (
  is  => 'ro',
  isa => PositiveMillicents,
  coerce => 1,
);

sub unapplied_amount {
  my ($self) = @_;
  return $self->amount - $self->accountant->from_credit($self)->total;
}

has created_at => (
  is   => 'ro',
  isa  => 'Moonpig::DateTime',
  default  => sub { Moonpig->env->now },
  required => 1,
);

sub STICK_PACK {
  my ($self) = @_;

  return {
    type   => $self->type,
    guid   => $self->guid,
    created_at => $self->created_at,
    amount => $self->amount,
    unapplied_amount => $self->unapplied_amount,
  };
}

sub type {
  my ($self) = @_;
  my $type = ref($self) || $self;
  $type =~ s/^(\w|::)+::Credit/Credit/;
  return $type;
}

1;

package Moonpig::Role::Credit;
# ABSTRACT: a ledger's credit toward paying invoices
use Moose::Role;

with(
  'Moonpig::Role::HasGuid',
  'Moonpig::Role::LedgerComponent',
  'Moonpig::Role::CanTransfer' => {
    -excludes => 'unapplied_amount',
    transferer_type => "credit"
  },
);

use Moonpig::Behavior::Packable;

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

PARTIAL_PACK {
  my ($self) = @_;

  return {
    type   => $self->type,
    created_at => $self->created_at,
    amount => $self->amount,
    unapplied_amount => $self->unapplied_amount,
  };
};

sub type {
  my ($self) = @_;
  my $type = ref($self) || $self;
  $type =~ s/^(\w|::)+::Credit/Credit/;
  return $type;
}

1;

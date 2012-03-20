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
  required => 1,
);

sub _amt_xferred_out {
  return $_[0]->accountant->from_credit($_[0])->total;
}

sub _amt_xferred_in {
  return $_[0]->accountant->to_credit($_[0])->total;
}

sub applied_amount {
  my ($self) = @_;
  my $amt = $self->_amt_xferred_out - $self->_amt_xferred_in;

  Moonpig::X->throw("more credit applied than initially provided")
    if $amt > $self->amount;

  return $amt;
}

sub unapplied_amount {
  my ($self) = @_;
  my $amt = $self->amount - $self->_amt_xferred_out + $self->_amt_xferred_in;

  if ($amt > $self->amount) {
    Moonpig::X->throw("more credit unapplied than initially provided");
  }

  return $amt;
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

sub is_refundable {
  $_[0]->does("Moonpig::Role::Credit::Refundable") ? 1 : 0;
}

1;

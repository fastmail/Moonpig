package Moonpig::Role::Credit;
# ABSTRACT: a ledger's credit toward paying invoices
use Moose::Role;

with(
  'Moonpig::Role::HasCreatedAt',
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

sub _get_amts {
  my ($self) = @_;

  my $in  = $self->_amt_xferred_in;
  my $out = $self->_amt_xferred_out;
  my $amt = $self->amount;

  # sanity check
  my $have = $amt - $out + $in;
  Moonpig::X->throw("more credit applied than initially provided")
    if $have > $amt;

  Moonpig::X->throw("credit's applied amount is negative")
    if $have < 0;

  return ($in, $out);
}

sub applied_amount {
  my ($self) = @_;

  my ($in, $out) = $self->_get_amts;

  return($out - $in);
}

sub current_allocation_pairs {
  my ($self) = @_;

  return $self->ledger->accountant->__compute_effective_transferrer_pairs({
    thing => $self,
    to_thing   => [ qw(cashout) ],
    from_thing => [ qw(consumer_funding debit) ],
    negative   => [ qw(cashout) ],
    upper_bound => $self->amount,
  });
}

sub unapplied_amount {
  my ($self) = @_;

  my ($in, $out) = $self->_get_amts;

  return($self->amount - $out + $in)
}

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

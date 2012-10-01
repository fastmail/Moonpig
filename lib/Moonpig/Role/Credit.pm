package Moonpig::Role::Credit;
# ABSTRACT: a ledger's credit toward paying invoices
use Moose::Role;

with(
  'Stick::Role::PublicResource',
  'Stick::Role::PublicResource::GetSelf',
  'Stick::Role::Routable::ClassAndInstance',
  'Stick::Role::Routable::AutoInstance',
  'Moonpig::Role::HasCreatedAt',
  'Moonpig::Role::HasGuid',
  'Moonpig::Role::LedgerComponent',
  'Moonpig::Role::CanTransfer' => {
    -excludes => 'unapplied_amount',
    transferer_type => "credit"
  },
);

use Moonpig::Behavior::Packable;

use List::AllUtils qw(min natatime);
use Moonpig::Types qw(PositiveMillicents);
use Moonpig::Util qw(class days pair_lefts);
use Stick::Publisher 0.307;
use Stick::Publisher::Publish 0.307;
require Stick::Role::Routable::AutoInstance;
Stick::Role::Routable::AutoInstance->VERSION(0.307);

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

sub type {
  my ($self) = @_;
  my $type = ref($self) || $self;
  $type =~ s/^(\w|::)+::Credit/Credit/;
  return $type;
}

sub is_refundable {
  $_[0]->does("Moonpig::Role::Credit::Refundable") ? 1 : 0;
}

publish dissolve => {
  -http_method => 'post',
} => sub {
  my ($self) = @_;

  my $ledger = $self->ledger;

  my @pairs = $self->current_allocation_pairs;

  my $cpa = $ledger->accountant;

  my $iter = natatime 2, @pairs;
  while (my ($object, $amount) = $iter->()) {
    Moonpig::X->throw("can't dissolve refunded credit")
      if $object->does("Moonpig::Role::Debit");

    $cpa->create_transfer({
      type => 'cashout',
      from => $object,
      to   => $self,
      amount => $amount,
    });

    $object->charge_current_invoice({
      extra_tags  => [ qw(reinvoice) ],
      amount      => $amount,
      description => "replace funds from " . $self->as_string,
    });

    if ($object->does('Moonpig::Role::Consumer::ByTime')) {
      my $two_weeks = Moonpig->env->now + days(14);
      $object->grace_until( $two_weeks )
        unless $object->grace_until && $object->grace_until > $two_weeks;
    }
  }

  Moonpig::X->throw("cashed out all allocations, but some balance is missing")
    unless $self->unapplied_amount == $self->amount;

  my $writeoff = $ledger->add_debit(class(qw(Debit::WriteOff)));

  $ledger->create_transfer({
    type  => 'debit',
    from  => $self,
    to    => $writeoff,
    amount  => $self->amount,
  });

  $ledger->perform_dunning; # this implies ->process_credits
};

sub _class_subroute { ... }

publish _extended_info => {
  -path        => 'extended-info',
  -http_method => 'get',
} => sub {
  my ($self) = @_;

  my $pack = $self->STICK_PACK;
  $pack->{refundable_amount} = min(
    $self->unapplied_amount,
    $self->ledger->amount_available,
  );

  return $pack;
};

PARTIAL_PACK {
  my ($self) = @_;

  return {
    type   => $self->type,
    amount => $self->amount,
    unapplied_amount => $self->unapplied_amount,
  };
};

1;

package Moonpig::Role::Invoice;
# ABSTRACT: a collection of charges to be paid by the customer
use Moose::Role;

with(
  'Moonpig::Role::HasLineItems',
  'Moonpig::Role::HasCreatedAt',
  'Moonpig::Role::LedgerComponent',
  'Moonpig::Role::HandlesEvents',
  'Moonpig::Role::HasGuid' => { -excludes => 'ident' },
  'Stick::Role::PublicResource',
  'Stick::Role::PublicResource::GetSelf',
  'Stick::Role::Routable::ClassAndInstance',
  'Stick::Role::Routable::AutoInstance',
);

use Carp qw(confess croak);
use Moonpig::Behavior::EventHandlers;
use Moonpig::Behavior::Packable;

use List::AllUtils qw(uniq);
use Moonpig::Logger '$Logger';
use Moonpig::Types qw(Credit GUID Time);
use Moonpig::Util qw(class event sumof);
use Moonpig::X;
use MooseX::SetOnce;

use Stick::Util qw(ppack true false);
use Stick::Types qw(StickBool);

use namespace::autoclean;

sub charge_role { 'InvoiceCharge' }

sub accepts_line_item {
  my ($self, $line_item) = @_;
  $line_item->does("Moonpig::Role::InvoiceCharge") ||
  $line_item->does("Moonpig::Role::LineItem::Discount") ||
  $line_item->does("Moonpig::Role::LineItem::Note");
}

has paid_at => (
  isa => Time,
  init_arg  => undef,
  reader    => 'paid_at',
  predicate => 'is_paid',
  writer    => '__set_paid_at',
  traits => [ qw(SetOnce) ],
);

sub mark_paid {
  my ($self) = @_;
  confess("Tried to pay open invoice " . $self->guid) if $self->is_open;
  $self->__set_paid_at( Moonpig->env->now )
}

sub is_unpaid {
  return ! $_[0]->is_paid
}

sub is_payable {
  return( $_[0]->is_closed
    && $_[0]->is_unpaid
    && ! $_[0]->is_abandoned
    && $_[0]->isnt_quote
  );
}

has _abandoned_at => (
  is => 'rw',
  isa => Time,
  reader    => 'abandoned_at',
  predicate => 'is_abandoned',
  init_arg => undef,
  traits => [ qw(SetOnce) ],
);

has abandoned_in_favor_of => (
  is => 'rw',
  isa => GUID,
  traits => [ qw(SetOnce) ],
);

sub mark_abandoned {
  my ($self) = @_;
  return if $self->is_abandoned;
  $self->_abandoned_at(Moonpig->env->now);
}

has is_internal => (
  reader => 'is_internal',
  writer => '_set_is_internal',
  isa    => StickBool,
  traits => [ qw(SetOnce) ],
  predicate => '_has_is_internal',
);

sub mark_internal {
  my ($self) = @_;
  Moonpig::X->throw("tried to internalize a closed invoice")
    if $self->is_closed;
  $self->_set_is_internal(true);
}

after mark_closed => sub {
  $_[0]->_set_is_internal(false) unless $_[0]->_has_is_internal;
};

# transfer non-abandoned charges to ledger's current open invoice
sub abandon {
  my ($self) = @_;
  $self->ledger->abandon_invoice($self);
}

sub abandon_if_empty {
  my ($self) = @_;
  return if $self->is_open;
  return if $self->is_paid;
  return if $self->unabandoned_items;
  $self->abandon_without_replacement;
  $self->mark_abandoned;
}

# transfer non-abandoned charges to specified open invoice,
# or just discard them if $new_invoice is omitted
sub abandon_with_replacement {
  my ($self, $new_invoice) = @_;
  confess "Can't abandon open invoice " . $self->guid
    unless $self->is_closed;

  confess "Can't abandon already-paid invoice " . $self->guid
    unless $self->is_unpaid;

  my @abandoned_items   = $self->abandoned_items;
  my @unabandoned_items = $self->unabandoned_items;

  confess "Can't abandon invoice " . $self->guid . " with no abandoned charges"
    if $self->has_items and ! @abandoned_items;

  if ($new_invoice) {
    confess "Can't replace abandoned invoice with closed invoice"
      . $new_invoice->guid
        if $new_invoice->is_closed;

    # XXX This discards non-charge items. Is that correct? mjd 2012-07-11
    for my $charge (@unabandoned_items) {
      $new_invoice->add_charge($charge);
    }

    $self->abandoned_in_favor_of($new_invoice->guid)
  }

  $self->mark_abandoned;

  return $new_invoice;
}

sub add_line_item { $_[0]->_add_item($_[1]) }

sub abandon_without_replacement { $_[0]->abandon_with_replacement(undef) }

# use this when we're sure we'll never be paid for this invoice
# abandon all charges and then the invoice itself.
sub cancel {
  my ($self) = @_;
  $_->mark_abandoned for $self->all_charges;
  $self->abandon_without_replacement();
}

implicit_event_handlers {
  return {
    'paid' => {
      redistribute   => Moonpig::Events::Handler::Method->new('_pay_charges'),
    }
  };
};

sub _pay_charges {
  my ($self, $event) = @_;

  # Include non-charge items, and charges that are not abandoned
  my @items = $self->unabandoned_items;

  my $collection = $self->ledger->consumer_collection;
  my @guids     = uniq map { $_->owner_guid } @items;
  my @consumers = grep { $_->is_active || $_->is_expired }
                  map  {; $collection->find_by_guid({ guid => $_ }) } @guids;

  $_->acquire_funds for @consumers;

  $_->handle_event($event) for @items;
}

sub __execute_charges_for {
  my ($self, $consumer) = @_;

  my $ledger = $self->ledger;

  Moonpig::X->throw("can't execute charges on unpaid invoice")
    unless $self->is_paid;

  Moonpig::X->throw("can't execute charges on open invoice")
    unless $self->is_closed;

  my @charges =
    grep { ! $_->is_executed && ! $_->is_abandoned }
    grep { $_->owner_guid eq $consumer->guid } $self->all_charges;

  # Try to apply non-refundable credit first.  Within that, go for smaller
  # credits first. -- rjbs, 2012-03-06
  my @credits = sort { $b->is_refundable   <=> $a->is_refundable
                   || $a->unapplied_amount <=> $b->unapplied_amount }
                grep { $_->unapplied_amount }
                $ledger->credits;

  for my $charge (@charges) {
    my $still_need = $charge->amount;
    for my $credit (@credits) {
      my $to_xfer = $credit->unapplied_amount >= $still_need
                  ? $still_need
                  : $credit->unapplied_amount;
      $ledger->accountant->create_transfer({
        type => 'consumer_funding',
        from => $credit,
        to   => $consumer,
        amount => $to_xfer,
      });
      $still_need -= $to_xfer;
      last if $still_need == 0;
    }

    $charge->__set_executed_at( Moonpig->env->now );
  }
}

sub ident {
  $_[0]->ledger->_invoice_ident_registry->{ $_[0]->guid } // $_[0]->guid;
}

sub is_quote {
  my ($self) = @_;
  return (
    ($self->can("quote_expiration_time") && ! $self->is_executed)
    ? true
    : false
  )
}
sub isnt_quote { ! $_[0]->is_quote }

PARTIAL_PACK {
  my ($self) = @_;

  return ppack({
    ident        => $self->ident,
    total_amount => $self->total_amount,
    paid_at      => $self->paid_at,
    closed_at    => $self->closed_at,
    created_at   => $self->date,
    charges      => [ map {; ppack($_) } $self->all_items ],
    is_quote     => $self->is_quote,
    is_internal  => $self->is_internal,
    abandoned_at => $self->abandoned_at,
  });
};

sub _class_subroute { return }

1;

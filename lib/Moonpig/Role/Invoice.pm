package Moonpig::Role::Invoice;
# ABSTRACT: a collection of charges to be paid by the customer
use Moose::Role;

with(
  'Moonpig::Role::HasCharges' => { charge_role => 'InvoiceCharge' },
  'Moonpig::Role::LedgerComponent',
  'Moonpig::Role::HandlesEvents',
  'Moonpig::Role::HasGuid' => { -excludes => 'ident' },
  'Moonpig::Role::CanTransfer' => { transferer_type => "invoice" },
  'Stick::Role::PublicResource',
  'Stick::Role::PublicResource::GetSelf',
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

use Stick::Util qw(ppack);

use namespace::autoclean;

has created_at => (
  is   => 'ro',
  isa  => Time,
  default => sub { Moonpig->env->now },
  traits => [ qw(SetOnce) ],
);

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

# transfer non-abandoned charges to ledger's current open invoice
sub abandon {
  my ($self) = @_;
  $self->ledger->abandon_invoice($self);
}

# transfer non-abandoned charges to specified open invoice,
# or just discard them if $new_invoice is omitted
sub abandon_with_replacement {
  my ($self, $new_invoice) = @_;
  confess "Can't abandon open invoice " . $self->guid
    unless $self->is_closed;

  confess "Can't abandon already-paid invoice " . $self->guid
    unless $self->is_unpaid;

  confess "Can't abandon invoice " . $self->guid . " with no abandoned charges"
    unless grep $_->is_abandoned, $self->all_charges;

  if ($new_invoice) {
    confess "Can't replace abandoned invoice with closed invoice"
      . $new_invoice->guid
        if $new_invoice->is_closed;

    for my $charge (grep ! $_->is_abandoned, $self->all_charges) {
      $new_invoice->_add_charge($charge);
    }

    $self->abandoned_in_favor_of($new_invoice->guid)
  }

  $self->mark_abandoned;

  return $new_invoice;
}

sub abandon_without_replacement { $_[0]->abandon_with_replacement(undef) }

# use this when we're sure we'll never be paid for this invoice
# abandon all charges and then the invoice itself.
sub cancel {
  my ($self) = @_;
  $_->mark_abandoned for $self->all_charges;
  $self->abandon_without_replacement();
}

# XXX: delete this method -- rjbs, 2012-03-07
sub amount_due {
  my ($self) = @_;
  my $total = $self->total_amount;
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

  my @charges = $self->all_charges;

  my $collection = $self->ledger->consumer_collection;
  my @guids     = uniq map { $_->owner_guid } @charges;
  my @consumers = grep { $_->is_active }
                  map  {; $collection->find_by_guid({ guid => $_ }) } @guids;

  $_->_try_to_get_funding for @consumers;

  $_->handle_event($event) for @charges;

}

sub ident {
  $_[0]->ledger->_invoice_ident_registry->{ $_[0]->guid } // $_[0]->guid;
}

PARTIAL_PACK {
  my ($self) = @_;

  return ppack({
    ident        => $self->ident,
    total_amount => $self->total_amount,
    paid_at      => $self->paid_at,
    closed_at    => $self->closed_at,
    created_at   => $self->date,
    charges      => [ map {; ppack($_) } $self->all_charges ],
  });
};

1;

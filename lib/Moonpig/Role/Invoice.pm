package Moonpig::Role::Invoice;
# ABSTRACT: a collection of charges to be paid by the customer
use Moose::Role;

with(
  'Moonpig::Role::HasCharges' => { charge_role => 'InvoiceCharge' },
  'Moonpig::Role::LedgerComponent',
  'Moonpig::Role::HandlesEvents',
  'Moonpig::Role::HasGuid',
  'Moonpig::Role::CanTransfer' => { transferer_type => "invoice" },
  'Stick::Role::PublicResource',
  'Stick::Role::PublicResource::GetSelf',
);

use Carp qw(confess croak);
use Moonpig::Behavior::EventHandlers;
use Moonpig::Behavior::Packable;

use Moonpig::Util qw(class event sumof);
use Moonpig::Types qw(Credit Time);
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

# transfer non-abandoned charges to specified open invoice
sub abandon_with_replacement {
  my ($self, $new_invoice) = @_;
  $new_invoice || croak("abandon_with_replacement missing new invoice argument");
  confess "Can't replace abandoned invoice with closed invoice" . $new_invoice->guid
    if $new_invoice->is_closed;

  confess "Can't abandon open invoice " . $self->guid
    unless $self->is_closed;

  confess "Can't abandon already-paid invoice " . $self->guid
    unless $self->is_unpaid;

  confess "Can't abandon invoice " . $self->guid . " with no abandoned charges"
    unless grep $_->is_abandoned, $self->all_charges;

  for my $charge (grep ! $_->is_abandoned, $self->all_charges) {
    $new_invoice->_add_charge($charge);
  }

  $self->mark_abandoned;

  return $new_invoice;
}

sub amount_due {
  my ($self) = @_;
  my $total = $self->total_amount;
  my $paid  = $self->ledger->accountant->to_invoice($self)->total;

  return $total - $paid;
}

implicit_event_handlers {
  return {
    'paid' => {
      redistribute   => Moonpig::Events::Handler::Method->new('_pay_charges'),
      fund_consumers => Moonpig::Events::Handler::Method->new('_fund_consumers'),
    }
  };
};

sub _pay_charges {
  my ($self, $event) = @_;
  $_->handle_event($event) for $self->all_charges;
}

sub _bankable_charges_by_consumer {
  my ($self) = @_;
  my %res;
  for my $charge ( $self->all_charges ) {
    push @{$res{$charge->owner_guid}}, $charge;
  }
  return \%res;
}

sub _fund_consumers {
  my ($self, $event) = @_;
  my $by_consumer = $self->_bankable_charges_by_consumer;

  while (my ($consumer_guid, $charges) = each %$by_consumer) {
    # XXX This method path is too long.  The consumer collection should handle
    # ->find_consumer_by_guid.
    my $consumer = $self->ledger->consumer_collection->find_by_guid({
      guid => $consumer_guid,
    });
    my $total = sumof { $_->amount } @$charges;

    $self->ledger->create_transfer({
      type   => 'consumer_funding',
      from   => $self,
      to     => $consumer,
      amount => $total,
    });
  }
}

PARTIAL_PACK {
  my ($self) = @_;

  return ppack({
    total_amount => $self->total_amount,
    amount_due   => $self->amount_due,
    paid_at      => $self->paid_at,
    closed_at    => $self->closed_at,
    created_at   => $self->date,
    charges      => [ map {; ppack($_) } $self->all_charges ],
  });
};

1;

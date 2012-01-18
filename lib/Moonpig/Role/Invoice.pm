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

use Moonpig::Behavior::EventHandlers;
use Moonpig::Behavior::Packable;

use Moonpig::Util qw(class event sumof);
use Moonpig::Types qw(Credit Time);
use Moonpig::X;

use Stick::Types qw(StickBool);
use Stick::Util qw(ppack true false);

use namespace::autoclean;

has created_at => (
  is   => 'ro',
  isa  => Time,
  default => sub { Moonpig->env->now },
);

has paid => (
  isa => StickBool,
  init_arg => undef,
  coerce   => 1,
  default  => 0,
  reader   => 'is_paid',
  writer   => '__set_paid',
);

sub mark_paid { $_[0]->__set_paid(true) }

sub is_unpaid {
  my $value = $_[0]->is_paid;
  return ! $value->is_true
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
    is_paid      => $self->is_paid,
    is_closed    => $self->is_closed,
    date         => $self->date,
    charges      => [ map {; ppack($_) } $self->all_charges ],
  });
};

1;

package Moonpig::Role::Invoice;
# ABSTRACT: a collection of charges to be paid by the customer
use Moose::Role;

with(
  'Moonpig::Role::HasCharges' => { charge_role => 'InvoiceCharge' },
  'Moonpig::Role::LedgerComponent',
  'Moonpig::Role::HandlesEvents',
  'Moonpig::Role::HasGuid',
  'Moonpig::Role::Payable',
  'Stick::Role::PublicResource',
  'Stick::Role::PublicResource::GetSelf',
);

use Moonpig::Behavior::EventHandlers;
use Moonpig::Behavior::Packable;

use Moonpig::Util qw(class event sum);
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

implicit_event_handlers {
  return {
    'paid' => {
      redistribute => Moonpig::Events::Handler::Method->new('_pay_charges'),
      create_banks => Moonpig::Events::Handler::Method->new('_create_banks'),
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
  for my $charge ( grep { $_->does("Moonpig::Role::InvoiceCharge::Bankable") }
                     $self->all_charges ) {
    push @{$res{$charge->owner_guid}}, $charge;
  }
  return \%res;
}

sub _create_banks {
  my ($self, $event) = @_;
  my $by_consumer = $self->_bankable_charges_by_consumer;

  while (my ($consumer_guid, $charges) = each %$by_consumer) {
    # XXX This method path is too long.  The consumer collection should handle
    # ->find_consumer_by_guid.
    my $consumer = $self->ledger->consumer_collection->find_by_guid({ guid => $consumer_guid });
    my $total = sum(map $_->amount, @$charges);

    my $bank = $self->ledger->add_bank(
      class(qw(Bank)),
      {
        amount => $total,
      });

    $consumer->_set_bank($bank);
  }
}

PARTIAL_PACK {
  my ($self) = @_;

  return ppack({
    total_amount => $self->total_amount,
    is_paid      => $self->is_paid,
    is_closed    => $self->is_closed,
    date         => $self->date,
    charges      => [ map {; ppack($_) } $self->all_charges ],
  });
};

1;

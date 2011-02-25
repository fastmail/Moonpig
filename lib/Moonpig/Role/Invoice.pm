package Moonpig::Role::Invoice;
# ABSTRACT: a collection of charges to be paid by the customer
use Moose::Role;

with(
  'Moonpig::Role::ChargeTreeContainer' => { charges_handle_events => 1 },
  'Moonpig::Role::LedgerComponent',
  'Moonpig::Role::HandlesEvents',
  'Moonpig::Role::HasGuid',
  'Moonpig::Role::Payable',
);

use Moonpig::Behavior::EventHandlers;

use Moonpig::Util qw(event);
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
  writer   => '__paid',
);

sub mark_paid { $_[0]->__paid(true) }

sub is_unpaid {
  my $value = $_[0]->is_paid;
  return ! $value->is_true
}

implicit_event_handlers {
  return {
    'paid' => {
      redistribute => Moonpig::Events::Handler::Method->new('_pay_charges'),
    }
  };
};

sub _pay_charges {
  my ($self, $event) = @_;

  $self->charge_tree->apply_to_all_charges(sub { $_->handle_event($event) });
}

sub STICK_PACK {
  my ($self) = @_;

  return ppack({
    guid         => $self->guid,
    total_amount => $self->total_amount,
    is_paid      => $self->is_paid,
    is_closed    => $self->is_closed,
    date         => $self->date,
  });
}

1;

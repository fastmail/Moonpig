package Moonpig::Role::InvoiceCharge;
use Moose::Role;
with(
  'Moonpig::Role::Charge',
  'Moonpig::Role::HandlesEvents',
);

use namespace::autoclean;
use Moonpig::Behavior::EventHandlers;
use Moonpig::Types qw(GUID Time);
use MooseX::SetOnce;

# translate ->new({consumer => ... }) to
# ->new({ ledger_guid => ..., owner_guid => ... })
around BUILDARGS => sub {
  my $orig  = shift;
  my $class = shift;
  my $args = shift;

  if (my $consumer = delete $args->{consumer}) {
    $args->{owner_guid}  ||= $consumer->guid;
    $args->{ledger_guid} ||= $consumer->ledger->guid;
  }

  return $class->$orig($args, @_);
};

has owner_guid => (
  is   => 'ro',
#  does => 'Moonpig::Role::Consumer',
  isa => GUID,
  required => 1,
);

sub owner {
  my ($self) = @_;
  $self->ledger->consumer_collection
    ->find_by_guid({ guid => $self->owner_guid });
}

has ledger_guid => (
  is   => 'ro',
#  does => 'Moonpig::Role::Ledger',
  isa => GUID,
  required => 1,
);

has abandoned_date => (
  is => 'rw',
  isa => Time,
  predicate => 'is_abandoned',
  traits => [ qw(SetOnce) ],
);

sub counts_toward_total { ! $_[0]->is_abandoned }

sub mark_abandoned {
  my ($self) = @_;
  $self->abandoned_date( Moonpig->env->now );
}

sub ledger {
  my ($self) = @_;
  Moonpig->env->storage->retrieve_ledger_for_guid($self->ledger_guid);
}

implicit_event_handlers {
  return {
    'paid' => {
      'default' => Moonpig::Events::Handler::Noop->new,
    },
  }
};

1;

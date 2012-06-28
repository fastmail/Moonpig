package Moonpig::Role::Invoice::Quote;
# ABSTRACT: like an invoice, but doesn't expect to be paid

use Carp qw(confess croak);
use Moonpig;
use Moonpig::Types qw(GUID Time XID);
use Moonpig::Util qw(days);
use Moose::Role;
use Stick::Publisher;
use Stick::Publisher::Publish;
use MooseX::SetOnce;
use Moose::Util::TypeConstraints qw(union);

use Moonpig::Behavior::Packable;

with(
  'Moonpig::Role::Invoice'
);

# XXX better name here
has executed_at => (
  is   => 'rw',
  isa  => Time,
  traits => [ qw(SetOnce) ],
  predicate => 'is_executed',
);

sub mark_executed {
  my ($self) = @_;
  confess sprintf "Can't execute open quote %s", $self->guid
    unless $self->is_closed;
  $self->executed_at(Moonpig->env->now);
}

has quote_expiration_time => (
  is => 'rw',
  isa => Time,
  predicate => 'has_quote_expiration_time',
  default => sub { Moonpig->env->now + days(30) },
);

sub quote_has_expired {
  my ($self) = @_;
  $self->has_quote_expiration_time &&
    Moonpig->env->now->follows($self->quote_expiration_time);
}

has attachment_point_guid => (
  is => 'rw',
  isa => union([GUID, 'Undef']),
  traits => [ qw(SetOnce) ],
);

# If this quote is a psync quote, we record the XID of the service for
# which it psyncs.
has psync_for_xid => (
  is => 'ro',
  isa => XID,
  predicate => 'is_psync_quote',
);

sub has_attachment_point { defined $_[0]->attachment_point_guid }

# A quote quotes the price to continue service in a particular way from a particular consumer.
# If service continues from that consumer in a different way, the quote is obsolete.
sub is_obsolete {
  my ($self) = @_;
  my $xid = $self->first_consumer->xid;
  my $active = $self->ledger->active_consumer_for_xid($xid);
  ! $self->can_be_attached_to( $active );
}

sub can_be_attached_to {
  my ($self, $potential_target) = @_;
  @_ == 2 or confess "Missing argument to Quote->can_be_attached_to";

  # Even if there was service before, and it has expired, it's still
  # okay to execute this quote to continue service.
  return 1 unless $potential_target;  # Not obsolete

  # But if the quote was to start fresh service, and the service
  # started differently, the quote is obsolete.
  return () unless $self->has_attachment_point;

  # If there is active service, and the quote is to extend that
  # service, it must be extended from the same point.
  return $self->attachment_point_guid eq $potential_target->guid;
}

before _pay_charges => sub {
  my ($self, @args) = @_;
  confess sprintf "Can't pay charges on unexecuted quote %s", $self->guid
    unless $self->is_executed;
};

has first_consumer_guid => (
  is => 'rw',
  isa => GUID,
  traits => [ qw(SetOnce) ],
  predicate => 'has_first_consumer',
);

sub first_consumer {
  my ($self) = @_;
  confess $self->ident . " has no first consumer"
    unless $self->has_first_consumer;

  $self->ledger->consumer_collection
    ->find_by_guid({ guid => $self->first_consumer_guid });
}

sub record_first_consumer {
  my ($self, $consumer) = @_;

  $self->first_consumer_guid($consumer->guid);
}

publish execute => { -http_method => 'post', -path => 'execute' } => sub {
  my ($self) = @_;

  if ($self->quote_has_expired) {
    confess sprintf "Can't execute quote '%s'; it expired at %s\n",
      $self->guid, $self->quote_expiration_time->iso;
  }

  if ($self->is_abandoned) {
    confess sprintf "Can't execute quote '%s'; it was abandoned at %s\n",
      $self->guid, $self->abandoned_at->iso;
  }

  # If there get to be too many of these conditionals, we should split
  # psync functionality out of Quote.pm. -- 20120614 mjd
  unless ($self->is_psync_quote) {
    my $first_consumer = $self->first_consumer;
    my $xid = $first_consumer->xid;

    my $attachment_target = $self->target_consumer($xid);

    unless ($self->can_be_attached_to( $attachment_target ) ) {
      Moonpig::X->throw(
        "can't execute obsolete quote",
        quote_guid => $self->guid,
        xid => $xid,
        expected_attachment_point => $self->attachment_point_guid,
        active_attachment_point => $attachment_target && $attachment_target->guid
       );
    }

    if ($attachment_target) {
      $attachment_target->replacement($first_consumer);
    } else {
      $first_consumer->become_active;
    }
  }

  $self->mark_executed;

  return $self;
};

sub target_consumer {
  my ($self, $xid) = @_;
  $xid ||= $self->first_consumer->xid;
  my $active = $self->ledger->active_consumer_for_xid( $xid );
  return($active ? $active->replacement_chain_end : undef);
}

after mark_closed => sub {
  my ($self, @args) = @_;
  $self->record_expected_attachment_point();
};

sub record_expected_attachment_point {
  my ($self) = @_;
  my $attachment_point = $self->target_consumer;
  my $guid = $attachment_point ? $attachment_point->guid : undef;
  $self->attachment_point_guid($guid);
}

PARTIAL_PACK {
  my ($self) = @_;

  return {
    executed_at => $self->executed_at,
  };
};

1;

package Moonpig::Role::Invoice::Quote;
# ABSTRACT: like an invoice, but doesn't expect to be paid

use Carp qw(confess croak);
use Moonpig;
use Moonpig::Types qw(GUID Time);
use Moonpig::Util qw(days);
use Moose::Role;
use MooseX::SetOnce;
use Moose::Util::TypeConstraints qw(union);

with(
  'Moonpig::Role::Invoice'
);

# requires qw(is_quote is_invoice);

# XXX better name here
has promoted_at => (
  is   => 'rw',
  isa  => Time,
  traits => [ qw(SetOnce) ],
  predicate => 'is_promoted',
);

sub mark_promoted {
  my ($self) = @_;
  confess sprintf "Can't promote open quote %s", $self->guid
    unless $self->is_closed;
  $self->promoted_at(Moonpig->env->now);
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
  predicate => 'has_attachment_point',
  traits => [ qw(SetOnce) ],
);

# A quote quotes the price to continue service in a particular way from a particular consumer.
# If service continues from that consumer in a different way, the quote is obsolete.
sub is_obsolete {
  my ($self, $active_consumer) = @_;

  # Even if there was service before, and it has expired, it's still
  # okay to execute this quote to continue service.
  return () unless $active_consumer;  # Not obsolete

  # But if the quote was to start fresh service, and the service
  # started differently, the quote is obsolete.
  return 1 unless $self->has_attachment_point;

  # If there is active service, and the quote is to extend that
  # service, it must be extended from the same point.
  return $self->attachment_point_guid ne $active_consumer->guid;
}

before _pay_charges => sub {
  my ($self, @args) = @_;
  confess sprintf "Can't pay charges on unpromoted quote %s", $self->guid
    unless $self->is_promoted;
};

sub first_consumer {
  my ($self) = @_;

  my @consumers = map $_->owner, $self->all_charges;
  my %consumers = map { $_->guid => $_ } @consumers;
  for my $consumer (@consumers) {
    $consumer->has_replacement && delete $consumers{$consumer->replacement->guid};
  }
  confess sprintf "Can't figure out the first consumer of quote %s", $self->guid
    unless keys %consumers == 1;
  my ($c) = values(%consumers);
  return $c;
}

sub execute {
  my ($self) = @_;

  if ($self->quote_has_expired) {
    confess sprintf "Can't execute quote '%s'; it expired at %s\n",
      $self->guid, $self->quote_expiration_time->iso;
  }

  my $first_consumer = $self->first_consumer;
  my $xid = $first_consumer->xid;
  my $active_consumer = $self->active_consumer($xid);

  if ($self->is_obsolete( $active_consumer ) ) {
    Moonpig::X->throw("can't execute obsolete quote",
                      quote_guid => $self->guid,
                      xid => $xid,
                      expected_attachment_point => $self->attachment_point_guid,
                      active_attachment_point => $active_consumer && $active_consumer->guid);
  }

  $self->mark_promoted;

  if ($active_consumer) {
    $active_consumer->replacement($first_consumer);
  } else {
    $first_consumer->become_active;
  }
}

sub active_consumer {
  my ($self, $xid) = @_;
  $xid ||= $self->first_consumer->xid;
  return $self->ledger->active_consumer_for_xid( $xid );
}

after mark_closed => sub {
  my ($self, @args) = @_;
  $self->record_expected_attachment_point();
};

sub record_expected_attachment_point {
  my ($self) = @_;
  my $attachment_point = $self->active_consumer;
  my $guid = $attachment_point ? $attachment_point->guid : undef;
  $self->attachment_point_guid($guid);
}

1;


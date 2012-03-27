package Moonpig::Role::Invoice::Quote;
# ABSTRACT: like an invoice, but doesn't expect to be paid

use Carp qw(confess croak);
use Moonpig;
use Moonpig::Types qw(Time);
use Moose::Role;
use MooseX::SetOnce;

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
);

sub quote_has_expired {
  Moonpig->env->now->precedes($_[0]->quote_expiration_time);
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
  return $c
}

1;


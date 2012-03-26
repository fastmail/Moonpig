package Moonpig::Role::Invoice::Quote;
# ABSTRACT: like an invoice, but doesn't expect to be paid

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
  is   => 'ro',
  isa  => Time,
  traits => [ qw(SetOnce) ],
  predicate => 'is_promoted',
);

has quote_expiration_time => (
  is => 'rw',
  isa => Time,
  predicate => 'has_quote_expiration_time',
);

sub quote_has_expired {
  Moonpig->env->now->precedes($_[0]->quote_expiration_time);
}

1;


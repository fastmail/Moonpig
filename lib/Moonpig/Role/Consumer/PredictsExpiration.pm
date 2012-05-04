package Moonpig::Role::Consumer::PredictsExpiration;
use Moose::Role;
# ABSTRACT: a consumer that can predict when it will expire

use namespace::autoclean;

require Stick::Publisher;
Stick::Publisher->VERSION(0.20110324);
use Stick::Publisher::Publish 0.20110324;
use Try::Tiny;

use List::AllUtils qw(any);
use Moonpig::Util qw(sumof);

use Moonpig::Behavior::Packable;

requires 'estimated_lifetime'; # TimeInterval, from created to predicted exp
requires 'expiration_date';    # Time, predicted exp date
requires 'remaining_life';     # TimeInterval, from now to predicted exp

publish replacement_chain_expiration_date => {} => sub {
  my ($self) = @_;

  my @chain = $self->replacement_chain;
  if (any {! $_->does('Moonpig::Role::Consumer::PredictsExpiration')} @chain) {
    Moonpig::X->throw("replacement in chain cannot predict expiration");
  }

  # XXX: HORRIBLE!!! This MUST MUST MUST be removed ASAP, but for now will
  # prevent users from seeing an exp. date for consumers that are not fully
  # paid. -- rjbs, 2012-04-26
  @chain = grep {; ! grep { ! $_->is_paid } $_->relevant_invoices } @chain;

  return($self->expiration_date + (sumof { $_->estimated_lifetime } @chain));
};

PARTIAL_PACK {
  my ($self) = @_;

  return try {
    my $exp_date = $self->replacement_chain_expiration_date;
    return { replacement_chain_expiration_date => $exp_date };
  } catch {
    die $_ unless try { $_->ident eq "can't compute funded lifetime of zero-cost consumer" };
    return { };
  };
};

1;

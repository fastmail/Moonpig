package Moonpig::Role::Consumer::PredictsExpiration;
use Moose::Role;
# ABSTRACT: a consumer that can predict when it will expire

use namespace::autoclean;

require Stick::Publisher;
Stick::Publisher->VERSION(0.20110324);
use Stick::Publisher::Publish 0.20110324;
use Try::Tiny;

use List::AllUtils qw(any);
use Moonpig::Behavior::Packable;
use Moonpig::Util qw(sumof);
use Moose::Util::TypeConstraints qw(maybe_type);
use Stick::Types qw(OptionalStickBool);

requires 'estimated_lifetime'; # TimeInterval, from activation to predicted exp
requires 'expiration_date';    # Time, predicted exp date

publish replacement_chain_expiration_date => {
  -http_method => 'get',
  include_expected_funds => OptionalStickBool,
} => sub {
  my ($self, $opts) = @_;

  my @chain = $self->replacement_chain;
  if (any {! $_->does('Moonpig::Role::Consumer::PredictsExpiration')} @chain) {
    Moonpig::X->throw("replacement in chain cannot predict expiration");
  }

  # XXX: HORRIBLE!!! This MUST MUST MUST be removed ASAP, but for now will
  # prevent users from seeing an exp. date for consumers that are not fully
  # paid. -- rjbs, 2012-04-26
  @chain = grep {; ! grep { ! $_->is_paid && ! $_->is_abandoned }
                    $_->relevant_invoices } @chain;

  my $amount_method =
    $opts->{include_expected_funds} ? "expected_funds"
      : "unapplied_amount";

  return $self->expiration_date +
    sumof {
      $_->_estimated_remaining_funded_lifetime({
        amount => $_->$amount_method,
        ignore_partial_charge_periods => 1,
      }) } @chain;
};

# Use an "around" modifier to override this if your consumer actually needs to do it
sub _estimated_remaining_funded_lifetime {
  confess("Role::Consumer::ByUsage::_estimated_remaining_funded_lifetime unimplemented");
}

PARTIAL_PACK {
  my ($self) = @_;

  return try {
    my $exp_date = $self->replacement_chain_expiration_date({ include_expected_funds => 0 });
    return { replacement_chain_expiration_date => $exp_date };
  } catch {
    die $_ unless try { $_->ident eq "can't compute funded lifetime of zero-cost consumer" };
    return { };
  };
};

1;

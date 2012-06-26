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
  my ($self, $_opts) = @_;
  my $opts = { %$_opts };
  $opts->{include_expected_funds} //= 0;
  $opts->{amount} //= $self->unapplied_amount;

  my @chain = $self->replacement_chain;
  if (any {! $_->does('Moonpig::Role::Consumer::PredictsExpiration')} @chain) {
    Moonpig::X->throw("replacement in chain cannot predict expiration");
  }

  # XXX 20120605 mjd We shouldn't be ignoring the partial charge
  # period here, which rounds down; we should be rounding UP to the
  # nearest complete charge period, because we are calculating a total
  # expiration date, and each consumer won't be activating its
  # successor until it expires, which occurs at the *end* of the last
  # paid charge period.
  return(Moonpig->env->now +
         $self->_estimated_remaining_funded_lifetime($opts) +
         (sumof {
           $_->_estimated_remaining_funded_lifetime({
             amount => $_->expected_funds(
               { include_unpaid_charges =>
                   $opts->{include_expected_funds} }),
             ignore_partial_charge_periods => 1,
           }) } @chain));
};

# Use an "around" modifier to override this if your consumer actually
# needs to do it
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

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
  include_unpaid_charges => OptionalStickBool,
} => sub {
  my ($self, $_opts) = @_;
  my $opts = { %$_opts };

  unless ($self->is_active) {
    # being active is equivalent to being the chain head -- rjbs, 2012-08-17
    Moonpig::X->throw("can't compute chain expiration date for non-head");
  }

  $opts->{include_unpaid_charges} //= 0;

  return $self->_replacement_chain_expiration_date($opts);
};

requires '_replacement_chain_expiration_date';

PARTIAL_PACK {
  my ($self) = @_;

  return try {
    return { } unless $self->is_active;
    my $exp_date = $self->replacement_chain_expiration_date({
      include_unpaid_charges => 0,
    });
    return { replacement_chain_expiration_date => $exp_date };
  } catch {
    die $_ unless try {
      $_->ident eq "can't compute funded lifetime of zero-cost consumer"
    };
    return { };
  };
};

1;

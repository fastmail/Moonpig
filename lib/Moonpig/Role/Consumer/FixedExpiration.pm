package Moonpig::Role::Consumer::FixedExpiration;
# ABSTRACT: something that uses up money stored in a bank
use Moose::Role;

use MooseX::Types::Moose qw(Str);
use Moonpig::Types qw(PositiveMillicents Time);

with(
  'Moonpig::Role::Consumer::AutoInvoicing',
  'Moonpig::Role::Consumer::ChargesBank',
);

use namespace::autoclean;

use Moonpig::Behavior::EventHandlers;

implicit_event_handlers {
  return {
    heartbeat => {
      charge => Moonpig::Events::Handler::Method->new(
        method_name => '_check_expiry',
      ),
    },
  };
};

# name taken from similar method in ByTime consumer
has expire_date => (
  is  => 'rw',
  isa => Time,
  required => 1,
);

has cost_amount => (
  is  => 'ro',
  isa => PositiveMillicents,
  required => 1,
);

has description => (
  is  => 'ro',
  isa => Str,
  required => 1,
);

sub costs_on {
  my ($self) = @_;

  return ( $self->description, $self->cost_amount );
}

sub _check_expiry {
  my ($self) = @_;

  return unless $self->expire_date <= Moonpig->env->now;

  $self->ledger->current_journal->charge({
    desc => $self->description,
    from => $self->bank,
    to   => $self,
    date => Moonpig->env->now,
    tags => $self->charge_tags,

    # no part of the amount should be applied, so I have expressly said
    # ->amount and not ->unapplied_amount; if the full amount is an
    # over-charge, there is a problem -- rjbs, 2011-07-06
    amount => $self->bank->amount,
  });

  $self->expire;
}

1;

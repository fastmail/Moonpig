package Moonpig::Role::Consumer::SelfFunding;
# ABSTRACT: a coupon that pays its own pay
use Moose::Role;

use Moonpig;
use Moonpig::Types qw(Factory PositiveMillicents Time TimeInterval);
use Moonpig::Util qw(class sum);
use MooseX::Types::Moose qw(ArrayRef Str);

use Moonpig::Behavior::Packable;

use Moonpig::Behavior::EventHandlers;
implicit_event_handlers {
  return {
    'activated' => {
      self_fund => Moonpig::Events::Handler::Method->new(
        method_name => 'self_fund',
      ),
    },
  }
};

with(
  'Moonpig::Role::Consumer',
);

use namespace::autoclean;

has self_funding_credit_roles => (
  is  => 'ro',
  isa => ArrayRef[ Str ],
  default => sub { [ 'Credit::Discount' ] },
);

has self_funding_credit_amount => (
  is  => 'ro',
  isa => PositiveMillicents,
  required => 1,
  default  => sub {
    my ($self) = @_;

    my @charge_pairs = $self->initial_invoice_charge_pairs;
    my $amount       = sum map  { $charge_pairs[$_] }
                           grep { $_ % 2 }
                           keys @charge_pairs;
    return $amount;
  },
);

sub self_fund {
  my ($self) = @_;

  my $amount = $self->amount;

  my $credit = $self->ledger->add_credit(
    class( $self->credit_roles ),
    { amount => $amount }
  );

  $self->ledger->accountant->create_transfer({
    type   => 'consumer_funding',
    from   => $credit,
    to     => $self,
    amount => $amount,
  });

  $self->acquire_funds;
}

# This hides the method from InvoiceOnCreation -- rjbs, 2012-03-19
around _invoice => sub {
  my ($orig, $self) = @_;
  # We don't actually invoice!
  return;
};

PARTIAL_PACK {
  return {
    self_funding_amount => $_[0]->self_funding_amount,
  };
};



1;

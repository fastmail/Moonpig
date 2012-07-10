package Moonpig::Role::Consumer::SelfFunding;
# ABSTRACT: a coupon that pays its own pay
use Moose::Role;

use Moonpig;
use Moonpig::Types qw(Factory PositiveMillicents Time TimeInterval);
use Moonpig::Util qw(class sum);
use MooseX::Types::Moose qw(ArrayRef Str);

use Moonpig::Behavior::Packable;

use Moonpig::Behavior::EventHandlers;

with(
  'Moonpig::Role::Consumer',
  'Moonpig::Role::StubBuild',
);

implicit_event_handlers {
  return {
    'activated' => {
      self_fund => Moonpig::Events::Handler::Method->new(
        method_name => 'self_fund',
      ),
    },
  }
};

use namespace::autoclean;

has self_funding_credit_roles => (
  isa => ArrayRef[ Str ],
  traits  => [ 'Array' ],
  default => sub { [ 'Credit::Discount' ] },
  handles => { self_funding_credit_roles => 'elements' },
);

has self_funding_credit_amount => (
  is  => 'ro',
  isa => PositiveMillicents,
  lazy => 1,
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

after BUILD => sub { $_[0]->self_funding_credit_amount };

sub self_fund {
  my ($self) = @_;

  my $amount = $self->self_funding_credit_amount;

  my $credit = $self->ledger->add_credit(
    class( $self->self_funding_credit_roles ),
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

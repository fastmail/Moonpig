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
  is  => 'rw',
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

sub adjust_self_funding_credit_amount {
  my ($self, $adjustment) = @_;
  $self->self_funding_credit_amount($adjustment + $self->self_funding_credit_amount);
}

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

# This completely overrides the behavior in ByTime -- mjd, 2012-07-09
around _issue_psync_charge => sub {
  my (undef, $self, @args) = @_;

  # If I am the active consumer, no additional funding is required
  return if $self->is_active;

  my $quote = $self->ledger->current_invoice;
  $quote->is_quote && $quote->is_psync_quote
    or die "Current journal is not a psync quote!";

  my @ancestors = $self->_previous_n_ancestors(5);
  my %is_ancestor = map { $_->guid => 1 } @ancestors;

  my @ancestor_charges = grep { $is_ancestor{$_->owner->guid} } $quote->all_charges;
  return unless @ancestor_charges;
  my $average_charge_amount = (sumof { $_->amount } @ancestor_charges) / @ancestor_charges;

  my $line_item = class("LineItem::PsyncB5G1Magic");
  $self->charge_current_invoice($line_item);
};

sub _previous_n_ancestors {
  my ($self, $n) = @_;

  my $root = $self->ledger->active_consumer_for_xid($self->xid);
  # get my ancestors
  my @chain = grep $_->replacement_chain_contains($self) && $_->guid ne $self->guid,
    $root, $root->replacement_chain;
  # Throw away all but the last $n of them, if requested
  if (defined $n) { shift @chain while @chain > $n }
  return @chain;
}

PARTIAL_PACK {
  return {
    self_funding_amount => $_[0]->self_funding_amount,
  };
};



1;

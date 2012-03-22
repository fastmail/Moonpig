package t::lib::Routine::XferChain;
use Test::Routine;

use Moonpig::Util qw(class dollars event years);
use Moonpig::Test::Factory qw(build_consumers);

sub fund {
  my ($self, $credit, $consumer, $amount) = @_;
  $credit->ledger->accountant->create_transfer({
    type => 'consumer_funding',
    from => $credit,
    to   => $consumer,
    amount => $amount,
  });
}

sub cashout {
  my ($self, $consumer, $credit, $amount) = @_;
  $credit->ledger->accountant->create_transfer({
    type => 'cashout',
    from => $consumer,
    to   => $credit,
    amount => $amount,
  });
}

sub refund {
  my ($self, $credit, $amount) = @_;

  my $ledger = $credit->ledger;
  my $refund = $ledger->add_debit(class(qw(Debit::Refund)));

  $ledger->accountant->create_transfer({
    type  => 'debit',
    from  => $credit,
    to    => $refund,
    amount  => $amount,
  });

  return $refund;
}

sub setup_xfers_abcxy {
  my ($self, $ledger) = @_;
  build_consumers(
    $ledger,
    { x => { template => 'dummy' }, y => { template => 'dummy' }, },
  ),

  my $x = $ledger->get_component('x');
  my $y = $ledger->get_component('y');

  $x->abandon_all_unpaid_charges;
  $y->abandon_all_unpaid_charges;

  my $credit_a = $ledger->add_credit(
    class('Credit::Simulated'),
    { amount => dollars(12) }
  );

  my $credit_b = $ledger->add_credit(
    class('Credit::Simulated'),
    { amount => dollars(12) }
  );

  my $credit_c = $ledger->add_credit(
    class('Credit::Simulated'),
    { amount => dollars(12) }
  );

  $ledger->name_component(credit_a => $credit_a);
  $ledger->name_component(credit_b => $credit_b);
  $ledger->name_component(credit_c => $credit_c);

  $self->fund   ($credit_a, $x, dollars( 5));
  $self->fund   ($credit_b, $x, dollars( 5));
  $self->fund   ($credit_a, $y, dollars( 5));
  $self->cashout($x, $credit_b, dollars( 5));
  my $r1 = $self->refund ($credit_b, dollars( 5));
  $self->fund   ($credit_b, $y, dollars( 5));
  $self->fund   ($credit_c, $x, dollars(10));
  $self->cashout($x, $credit_c, dollars(10));
  my $r2 = $self->refund ($credit_c, dollars( 5));
  $self->fund   ($credit_c, $x, dollars( 5));

  $ledger->name_component(refund_1 => $r1);
  $ledger->name_component(refund_2 => $r2);
  return;
}

sub setup_xfers_no_refunds {
  my ($self, $ledger) = @_;
  build_consumers(
    $ledger,
    { x => { template => 'dummy' }, y => { template => 'dummy' }, },
  ),

  my $x = $ledger->get_component('x');
  my $y = $ledger->get_component('y');

  $x->abandon_all_unpaid_charges;
  $y->abandon_all_unpaid_charges;

  my $credit_a = $ledger->add_credit(
    class('Credit::Simulated'),
    { amount => dollars(12) }
  );

  my $credit_b = $ledger->add_credit(
    class('Credit::Simulated'),
    { amount => dollars(12) }
  );

  $ledger->name_component(credit_a => $credit_a);
  $ledger->name_component(credit_b => $credit_b);

  $self->fund   ($credit_a, $x, dollars( 5));
  $self->fund   ($credit_b, $x, dollars( 5));
  $self->fund   ($credit_a, $y, dollars( 5));
  $self->cashout($x, $credit_a, dollars( 3));
  $self->fund   ($credit_a, $y, dollars( 2));
  $self->fund   ($credit_a, $x, dollars( 1));

  return;
}

sub guidify_pairs {
  my ($self, @pairs) = @_;
  blessed($_) && ($_ = $_->guid) for @pairs;
  return { @pairs };
}

1;

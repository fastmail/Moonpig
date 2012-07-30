package Moonpig::Test::Role::LedgerTester;
use Test::Routine;
# ABSTRACT: a test routine that works with ledgers

with(
  'Moonpig::Test::Role::UsesStorage',
);

use t::lib::Logger '$Logger';
use Moonpig::Util qw(class datetime sum to_dollars);
use Test::More;

use namespace::clean;

around run_test => sub {
  my ($orig, $self, @rest) = @_;
  Moonpig->env->stop_clock_at( datetime( jan => 1 ) );
  $self->$orig(@rest);
};

sub heartbeat_and_send_mail {
  my $self   = shift;
  my $ledger = shift;

  if (blessed($ledger)) {
    Moonpig->env->storage->do_rw(sub { $ledger->heartbeat; });
  } else {
    # It's a guid!
    Moonpig->env->storage->do_rw_with_ledger($ledger,
      sub { shift()->heartbeat; }
    );
  }

  Moonpig->env->process_email_queue;
}

sub pay_invoices {
  my ($self, $invoices) = @_;

  return unless @$invoices;

  my $ledger = $invoices->[0]->ledger;
  my $total = sum map { $_->total_amount } @$invoices;

  my $credit = $ledger->add_credit(
    class(qw(Credit::Simulated)),
    { amount => $total },
  );

  $ledger->process_credits;

  return $credit;
}

sub pay_payable_invoices {
  my ($self, $ledger, $expect, $desc) = @_;

  unless ($ledger->payable_invoices) {
    if (defined $expect) {
      is(0, $expect, $desc // "invoices payoff had expected cost");
    }
    return;
  }

  # There are unpaid invoices!
  my @invoices = $ledger->last_dunned_invoices;

  # 4. pay and apply payment to invoice
  my $credit = $self->pay_invoices(\@invoices);

  if (defined $expect) {
    is($credit->amount, $expect, $desc // "invoices payoff had expected cost");
  }

  $Logger->log([
    'LedgerTester just paid %s invoice(s) totalling $%0.2f',
    0+@invoices,
    to_dollars($credit->amount),
  ]);

  return $credit;
}

1;

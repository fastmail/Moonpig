package Moonpig::Test::Role::LedgerTester;
# ABSTRACT: a test routine that works with ledgers

use Test::Routine;

with(
  'Moonpig::Test::Role::UsesStorage',
);

use Moonpig::Logger '$Logger';
use Moonpig::Util qw(class datetime days sum sumof to_dollars);
use Test::More;

use namespace::clean;

around run_test => sub {
  my ($orig, $self, @rest) = @_;

  Moonpig->env->email_sender->clear_deliveries;
  Moonpig->env->stop_clock_at( datetime( jan => 1 ) );

  $self->$orig(@rest);

};

around _last_chance_before_test_ends => sub {
  my ($orig, $self) = @_;
  my @deliveries = $self->assert_n_deliveries(0, "no unexpected mail");
  for (map {; $_->{email} } @deliveries) {
    diag "-- Date: " . $_->header('Date');
    diag "   Subj: " . $_->header('Subject');
  }
  $self->$orig;
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

sub get_and_clear_deliveries {
  my ($self) = @_;

  Moonpig->env->process_email_queue;
  my @deliveries = Moonpig->env->email_sender->deliveries;
  Moonpig->env->email_sender->clear_deliveries;
  return @deliveries;
}

sub assert_n_deliveries {
  my ($self, $n, $msg) = @_;
  my @deliveries = $self->get_and_clear_deliveries;

  my $desc = "delivery count $n";
  $desc .= ": $msg" if defined $msg;

  local $Test::Builder::Level = $Test::Builder::Level + 1;
  is(@deliveries, $n, $desc);
  return @deliveries;
}

sub pay_invoices {
  my ($self, $invoices) = @_;

  return unless @$invoices;

  my $ledger = $invoices->[0]->ledger;
  my $total  = sum map { $_->total_amount } @$invoices;
  my $to_pay = $total - $ledger->amount_available;

  return $self->_pay_amount($ledger, $to_pay);
}

sub _pay_amount {
  my ($self, $ledger, $amount) = @_;

  my $credit = $ledger->add_credit(
    class(qw(Credit::Simulated)),
    { amount => $amount },
  );

  $ledger->process_credits;

  return $credit;
}

sub pay_amount_due {
  my ($self, $ledger, $expect, $desc) = @_;

  my $suffix = defined $expect
             ? sprintf('$%.2f', to_dollars($expect))
             : undef;

  unless ($ledger->amount_due) {
    if (defined $expect) {
      is(0, $expect, ($desc // "ledger payoff had expected cost") . ": $suffix");
    }
    return;
  }

  my %credit;

  my @invoices = $ledger->payable_invoices;
  if (@invoices) {
    $credit{invoice} = $self->pay_invoices(\@invoices);
  }

  my $extra;
  if ($ledger->amount_due) {
    $extra = 1;
    $credit{rest} = $self->_pay_amount($ledger, $ledger->amount_due);
  }

  my $total = sumof { $_->amount } values %credit;

  if (defined $expect) {
    is(
      $total,
      $expect,
      ($desc // "ledger payoff had expected cost") . ": $suffix"
    );
  }

  $Logger->log([
    'LedgerTester just paid %s invoice(s)%stotalling $%0.2f',
    0+@invoices,
    ($extra ? ' (and more) ' : ' '),
    to_dollars($total),
  ]);

  return $total;
}

# Wait until something happens
# (or, if supplied, until the current time is after $until)
sub wait_until {
  my ($self, $ledger, $predicate, $until, $step) = @_;
  $step //= days(1);

  my $elapsed = 0;
  until ($predicate->()) {
    return if defined($until) && Moonpig->env->now >= $until;
    Moonpig->env->elapse_time($step);

    $self->heartbeat_and_send_mail($ledger);
    $elapsed++;
  }

  my $days = $elapsed * $step / days(1);
  note "Predicate true after $days days (now " . Moonpig->env->now->iso . ")";
  return 1;
}

1;

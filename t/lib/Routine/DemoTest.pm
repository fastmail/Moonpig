package t::lib::Routine::DemoTest;
use Test::Routine;
use Test::More;

use t::lib::TestEnv;

with('Moonpig::Test::Role::UsesStorage');

use t::lib::Logger '$Logger';
use Moonpig::Test::Factory qw(do_with_fresh_ledger);

use Data::GUID qw(guid_string);
use Moonpig::Util qw(class days dollars sum sumof to_dollars);
use Moonpig::Types qw(GUID);

use t::lib::ConsumerTemplateSet::Demo;

use namespace::autoclean;

has xid => (
  is      => 'ro',
  isa     => 'Str',
  default => sub { 'yoyodyne:account:' . guid_string },
);

has invoices_to_pay => (
  is  => 'ro',
  isa => 'Int',
  required => 1,
  traits   => [ 'Number' ],
  handles  => {
    'dec_invoices_to_pay' => [ sub => 1 ],
  },
);

sub ledger {
  my ($self) = @_;
  Moonpig->env->storage->retrieve_ledger_for_guid($self->ledger_guid);
}

has ledger_guid => (
  is  => 'rw',
  isa => GUID,
);

sub active_consumer {
  my ($self) = @_;

  $self->ledger->active_consumer_for_xid( $self->xid );
}

sub pay_any_open_invoice {
  my ($self) = @_;

  Moonpig->env->storage->do_with_ledger($self->ledger_guid, sub {
    my ($ledger) = @_;

    if ($self->invoices_to_pay and $self->ledger->payable_invoices) {
      # There are unpaid invoices!
      my @invoices = $ledger->last_dunned_invoices;

      # 4. pay and apply payment to invoice

      my $total = sum map { $_->total_amount } @invoices;

      $ledger->add_credit(
        class(qw(Credit::Simulated)),
        { amount => $total },
      );

      $ledger->process_credits;

      $self->dec_invoices_to_pay for @invoices;
      $Logger->log([
        'DemoTestRoutine just paid %s invoice(s) totalling $%0.2f',
        0+@invoices,
        to_dollars($total),
      ]);
    }
  });
}

sub log_current_balance {
  my ($self) = @_;

  if (my $consumer = $self->active_consumer) {
    $Logger->log([ "CURRENTLY ACTIVE: %s", $consumer->ident ]);

    $Logger->log([
      "%s has %s in it",
      $consumer->ident,
      $consumer->unapplied_amount,
    ]);
  }
}

sub process_daily_assertions {
  my ($self, $day, $ledger) = @_;
}

sub setup_before_big_loop {
  my ($self, $ledger) = @_;
}

# The goal of our end to end test is to prove out the following:
#
# 1. create ledger
# 2. create consumer
# 3. charge, finalize, send invoice
# 4. pay and apply payment to invoice
# 5. fund the consumer
# 6. heartbeats, until...
# 7. consumer spends funds
# 8. until low-funds, goto 6
# 9. setup replacement
# 10. funds expire
# 11a. fail over (if replacement funded)
# 11b. cancel account (if replacement unfunded)

test "end to end demo" => sub {
  my ($self) = @_;

  Moonpig->env->stop_clock;

  do_with_fresh_ledger({}, sub {
    my ($ledger) = @_;

    $self->ledger_guid($ledger->guid);

    $ledger->add_consumer_from_template(
      'demo-service',
      {
        xid                => $self->xid,
        make_active        => 1,
      },
    );
  });

  Moonpig->env->storage->do_with_ledger($self->ledger_guid, sub {
    my ($ledger) = @_;

    $self->setup_before_big_loop;

    for my $day (1 .. 760) {
      Moonpig->env->process_email_queue;

      $self->process_daily_assertions($day, $ledger);

      $Logger->log([ 'TICK: %s', q{} . Moonpig->env->now ]) if $day % 30 == 0;

      $ledger->heartbeat;

      # Just a little more noise, to see how things are going.
      $self->log_current_balance if $day % 30 == 0;

      $self->pay_any_open_invoice;

      Moonpig->env->elapse_time(86400);
    }
  });

  Moonpig->env->storage->do_with_ledger($self->ledger_guid, sub {
    my ($ledger) = @_;
    my @consumers = $ledger->consumers;
    is(@consumers, 3, "three consumers created over the lifetime");

    my $active_consumer = $ledger->active_consumer_for_xid( $self->xid );
    is($active_consumer, undef, "...but they're all inactive now");

    # Every consumer wants $40 + $10, spent over the course of a year, charged
    # every 7 days.  That means each charge is...
    my $each_charge = dollars(50) / 365.25 * 7;

    # ...and that means we must not have any more credit left than that.
    $ledger->_collect_spare_change;
    my $avail = $ledger->amount_available;
    cmp_ok(
      $ledger->amount_available, '<', $each_charge,
      sprintf("ledger has less avail. credit (\$%.2f) than a charge (\$%.2f)",
        to_dollars($avail),
        to_dollars($each_charge),
      ),
    );
  });
};

1;

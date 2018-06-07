package t::lib::Routine::DemoTest;
use Test::Routine;
use Test::More;

use t::lib::TestEnv;

with('Moonpig::Test::Role::LedgerTester');

use Moonpig::Logger::Test '$Logger';
use Moonpig::Test::Factory qw(do_with_fresh_ledger);

use Data::GUID qw(guid_string);
use List::AllUtils qw(max);
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

around pay_amount_due => sub {
  my ($orig, $self, $ledger, @rest) = @_;

  return unless $self->invoices_to_pay;
  return $self->$orig($ledger, @rest);
};

after pay_invoices => sub {
  my ($self, $invoices) = @_;
  $self->assert_n_deliveries(1, "invoice (just paid)");
  $self->dec_invoices_to_pay for @$invoices;
};

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

      $self->pay_amount_due($ledger);

      Moonpig->env->elapse_time(86400);
    }
  });

  Moonpig->env->storage->do_with_ledger($self->ledger_guid, sub {
    my ($ledger) = @_;
    my @consumers = $ledger->consumers;
    is(@consumers, 3, "three consumers created over the lifetime");

    my $active_consumer = $ledger->active_consumer_for_xid( $self->xid );
    is($active_consumer, undef, "...but they're all inactive now");

    # ...and that means we must not have any more credit left than that.
    is(
      $ledger->amount_available,
      0,
      'any spare-change-collection went to journal (none were big)',
    );

    # Every consumer wants $40 + $10, spent over the course of a year, charged
    # every 7 days.  That means each day's total charge is...
    my $daily = $consumers[2]->calculate_total_charge_amount_on(
      Moonpig->env->now,
    );

    # We shouldn't have any transfers larger than that.  It would/could mean we
    # spare-change-collected something that could've paid for a whole day!
    my $max =
      max
      map {; $_->amount }
      $ledger->accountant->select({ target => $ledger->current_journal })->all;

    cmp_ok(
      $max, '<=', $daily,
      sprintf("no transfer was greater than the daily charge: %.2f <= %.2f",
        to_dollars($max),
        to_dollars($daily),
      ),
    );
  });
};

1;

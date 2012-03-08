#!/usr/bin/env perl
use Test::Routine;
use Test::Routine::Util -all;
use Test::More;

use t::lib::TestEnv;

with(
  'Moonpig::Test::Role::UsesStorage',
);

use t::lib::Logger '$Logger';
use Moonpig::Test::Factory qw(do_with_fresh_ledger);

use t::lib::TestEnv;

use Data::GUID qw(guid_string);
use Moonpig::Util qw(class days dollars sum sumof to_dollars);

use t::lib::ConsumerTemplateSet::Demo;

use namespace::autoclean;

has xid => (
  is      => 'ro',
  isa     => 'Str',
  default => sub { 'yoyodyne:account:' . guid_string },
);

has invoices_to_pay => (
  is      => 'ro',
  isa     => 'Int',
  default => 2,
  traits  => [ 'Number' ],
  handles => {
    'dec_invoices_to_pay' => [ sub => 1 ],
  },
);

my $Ledger_GUID;
sub Ledger {
  Moonpig->env->storage->retrieve_ledger_for_guid($Ledger_GUID);
}

sub active_consumer {
  my ($self) = @_;

  $self->Ledger->active_consumer_for_xid( $self->xid );
}

sub pay_any_open_invoice {
  my ($self) = @_;

  Moonpig->env->storage->do_with_ledger($Ledger_GUID, sub {
    my ($Ledger) = @_;

    if ($self->invoices_to_pay and $self->Ledger->payable_invoices) {
      # There are unpaid invoices!
      my @invoices = $Ledger->last_dunned_invoices;

      # 4. pay and apply payment to invoice

      my $total = sum map { $_->total_amount } @invoices;

      $Ledger->add_credit(
        class(qw(Credit::Simulated)),
        { amount => $total },
      );

      $Ledger->process_credits;

      $self->dec_invoices_to_pay;
      $Logger->('...');
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

sub process_daily_assertions {
  my ($self, $day, $Ledger) = @_;

  if ($day == 370) {
    # by this time, consumer 1 should've failed over to consumer 2
    my @consumers   = $Ledger->consumers;
    my $active      = $self->active_consumer;
    my ($inactive)  = grep { $_->guid ne $active->guid } @consumers;

    is(@consumers, 2, "by day 370, we have created a second consumer");
    is(
      $active->guid,
      $inactive->replacement->guid,
      "the active one is the replacement for the original one",
    );

    my @active_charges   = $active->all_charges;
    my @inactive_charges = $inactive->all_charges;

    is(@active_charges,   2, "the active one has charged once");
    is(@inactive_charges, 2, "the inactive one has charged once, too");
    cmp_ok(
      $active_charges[0]->date, '!=', $inactive_charges[0]->date,
      "...inactive and active on different days",
    );
  }

  if ($day == 740) {
    # by this time, consumer 2 should've failed over to consumer 3 and expired
    my @consumers   = $Ledger->consumers;
    my $active      = $self->active_consumer;

    is(@consumers, 3, "by day 740, we have created a third consumer");
    ok( ! $active,    "...and they are all inactive");
  }
}

test "end to end demo" => sub {
  my ($self) = @_;

  Moonpig->env->stop_clock;

  do_with_fresh_ledger({}, sub {
    my ($Ledger) = @_;
    $Ledger_GUID = $Ledger->guid;

    $Ledger->add_consumer_from_template(
      'demo-service',
      {
        xid                => $self->xid,
        make_active        => 1,
      },
    );
  });

  Moonpig->env->storage->do_with_ledger($Ledger_GUID, sub {
    my ($Ledger) = @_;

    for my $day (1 .. 760) {
      Moonpig->env->process_email_queue;

      $self->process_daily_assertions($day, $Ledger);

      $Logger->log([ 'TICK: %s', q{} . Moonpig->env->now ]) if $day % 30 == 0;

      $Ledger->heartbeat;

      # Just a little more noise, to see how things are going.
      $self->log_current_balance if $day % 30 == 0;

      $self->pay_any_open_invoice;

      Moonpig->env->elapse_time(86400);
    }
  });

  Moonpig->env->storage->do_with_ledger($Ledger_GUID, sub {
    my ($Ledger) = @_;
    my @consumers = $Ledger->consumers;
    is(@consumers, 3, "three consumers created over the lifetime");

    my $active_consumer = $Ledger->active_consumer_for_xid( $self->xid );
    is($active_consumer, undef, "...but they're all inactive now");

    # Every consumer wants $40 + $10, spent over the course of a year, charged
    # every 7 days.  That means each charge is...
    my $each_charge = dollars(50) / 365.25 * 7;

    # ...and that means we must not have any more credit left than that.
    $Ledger->_collect_spare_change;
    my $avail = $Ledger->amount_available;
    cmp_ok(
      $Ledger->amount_available, '<', $each_charge,
      sprintf("ledger has less avail. credit (\$%.2f) than a charge (\$%.2f)",
        to_dollars($avail),
        to_dollars($each_charge),
      ),
    );
  });
};

run_me;
done_testing;

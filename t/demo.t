#!/usr/bin/env perl
use Test::Routine;
use Test::Routine::Util -all;
use Test::More;

with(
  'Moonpig::Test::Role::UsesStorage',
);

use t::lib::Logger '$Logger';
use Moonpig::Test::Factory qw(build_ledger);

use Moonpig::Context::Test -all, '$Context';

use t::lib::TestEnv;

use Moonpig::Events::Handler::Code;

use Data::GUID qw(guid_string);
use List::Util qw(sum);
use Moonpig::Util qw(class days dollars event);

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

my $Ledger;

sub active_consumer {
  my ($self) = @_;

  $Ledger->active_consumer_for_xid( $self->xid );
}

sub pay_any_open_invoice {
  my ($self) = @_;

  if (
    $self->invoices_to_pay
    and
    grep { ! $_->is_open and ! $_->is_paid } $Ledger->invoices
  ) {
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
}

sub log_current_bank_balance {
  my ($self) = @_;

  if (my $consumer = $self->active_consumer) {
    $Logger->log([ "CURRENTLY ACTIVE: %s", $consumer->ident ]);

    if (my $bank = $consumer->bank) {
      $Logger->log([
        "%s still has %s in it",
        $consumer->bank->ident,
        $consumer->bank->unapplied_amount,
      ]);
    } else {
      $Logger->log([
        "%s is still without a bank",
        $consumer->ident,
      ]);
    }
  }
}

# The goal of our end to end test is to prove out the following:
#
# 1. create ledger
# 2. create consumer
# 3. charge, finalize, send invoice
# 4. pay and apply payment to invoice
# 5. create and link bank to consumer
# 6. heartbeats, until...
# 7. consumer charges bank
# 8. until low-funds, goto 6
# 9. setup replacement
# 10. funds expire
# 11a. fail over (if replacement funded)
# 11b. cancel account (if replacement unfunded)

sub process_daily_assertions {
  my ($self, $day) = @_;

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

  $Ledger = build_ledger();

  my $consumer;

  Moonpig->env->storage->do_rw(sub {
    Moonpig->env->save_ledger($Ledger);

    $consumer = $Ledger->add_consumer_from_template(
      'demo-service',
      {
        xid                => $self->xid,
        make_active        => 1,
      },
    );
  });

  for my $day (1 .. 760) {
    Moonpig->env->process_email_queue;

    $self->process_daily_assertions($day);

    Moonpig->env->storage->do_rw(sub {
      $Logger->log([ 'TICK: %s', q{} . Moonpig->env->now ]) if $day % 30 == 0;

      $Ledger->handle_event( event('heartbeat') );

      # Just a little more noise, to see how things are going.
      $self->log_current_bank_balance if $day % 30 == 0;

      $self->pay_any_open_invoice;

      Moonpig->env->elapse_time(86400);
    });
  }

  my @consumers = $Ledger->consumers;
  is(@consumers, 3, "three consumers created over the lifetime");

  my $active_consumer = $Ledger->active_consumer_for_xid( $self->xid );
  is($active_consumer, undef, "...but they're all inactive now");

  $Ledger->_collect_spare_change;
};

run_me;
done_testing;


use Carp qw(confess croak);
use Moonpig::DateTime;
use Moonpig::Util -all;
use Test::Routine;
use Test::More;
use Test::Routine::Util;

use t::lib::TestEnv;
use t::lib::Logger;

use Moonpig::Test::Factory qw(do_with_fresh_ledger);

with 'Moonpig::Test::Role::UsesStorage';

test "job-making invoice charge" => sub {
  do_with_fresh_ledger(
    {
      consumer => {
        class            => class('=t::lib::Role::Consumer::JobCharger'),
        replacement_plan => [ get => '/nothing' ],
        make_active      => 1,
      },
    },
    sub {
      my ($ledger) = @_;
      my $consumer = $ledger->get_component('consumer');

      ok($consumer, "set up consumer");
      ok($consumer->does('t::lib::Role::Consumer::JobCharger'),
         "consumer is correct type");

      ok(! $consumer->unapplied_amount, "still has no funds for now");

      $ledger->heartbeat;

      {
        my $jobs = Moonpig->env->storage->undone_jobs_for_ledger($ledger);
        my (@jobs) = grep { $_->job_type eq 'job.on.payment' } @$jobs;
        ok(@jobs == 0, "no on-payment jobs (yet)");
      }

      $ledger->credit_collection->add({
        type       => 'Simulated',
        attributes => { amount => dollars(3) },
      });

      $ledger->save;

      {
        my $jobs = Moonpig->env->storage->undone_jobs_for_ledger($ledger);
        my (@jobs) = grep { $_->job_type eq 'job.on.payment' } @$jobs;
        ok(@jobs == 1, "we made a job on payment!");
      }
    });
};

test "build_invoice_charge honored" => sub {
  my ($self) = @_;
  my $funky_role = "t::lib::Role::InvoiceCharge::JobCreator";

  do_with_fresh_ledger({
      consumer => {
        class => class("=t::lib::Role::Consumer::FunkyCharge"),
        charge_roles => [ "=$funky_role" ],
        xid         => "test:thing:xid",
        make_active => 1,
        replacement_plan => [ get => '/nothing' ],
      }}, sub {
    my ($ledger) = @_;

    my @charges = $ledger->current_invoice->all_charges;
    is(@charges, 1, "exactly 1 charge");
    ok($charges[0]->does($funky_role), "charge does role '$funky_role'");
  });
};

run_me;
done_testing;

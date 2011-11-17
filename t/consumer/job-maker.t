
use Carp qw(confess croak);
use Moonpig::DateTime;
use Moonpig::Util -all;
use Test::Routine;
use Test::More;
use Test::Routine::Util;

use t::lib::TestEnv;
use t::lib::Logger;

use Moonpig::Test::Factory qw(do_with_test_ledger);

with 'Moonpig::Test::Role::UsesStorage';

test "job-making invoice charge" => sub {
  do_with_test_ledger(
    {
      consumer => {
        class            => class('=t::lib::Role::Consumer::JobCharger'),
        replacement_plan => [ get => '/nothing' ],
        old_age          => days(30),
        make_active      => 1,
      },
    },
    sub {
      my ($ledger) = @_;
      my $consumer = $ledger->get_component('consumer');

      ok($consumer, "set up consumer");
      ok($consumer->does('t::lib::Role::Consumer::JobCharger'),
         "consumer is correct type");

      ok(! $consumer->has_bank, "still has no bank for now");

      $ledger->handle_event( event('heartbeat') );

      {
        my $jobs = Moonpig->env->storage->undone_jobs_for_ledger($ledger);
        my (@jobs) = grep { $_->job_type eq 'job.on.payment' } @$jobs;
        ok(@jobs == 0, "no on-payment jobs (yet)");
      }

      $ledger->credit_collection->add_credit({
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

run_me;
done_testing;

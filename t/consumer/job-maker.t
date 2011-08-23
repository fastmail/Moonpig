
use Carp qw(confess croak);
use Moonpig::DateTime;
use Moonpig::Util -all;
use Test::Routine;
use Test::More;
use Test::Routine::Util;

use t::lib::Factory qw(build);
use t::lib::Logger;

with 't::lib::Role::UsesStorage';

use Moonpig::Context::Test -all, '$Context';

test "job-making invoice charge" => sub {
  Moonpig->env->storage->do_rw(sub {
    my $stuff = build(
      consumer => {
        class            => class('=t::lib::Role::Consumer::JobCharger'),
        replacement_plan => [ get => '/nothing' ],
        old_age          => days(30),
        make_active      => 1,
      },
    );

    my $consumer = $stuff->{consumer};
    my $ledger   = $stuff->{ledger};

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

    # diag(explain(Stick::Util->ppack($ledger)));
    {
      my $jobs = Moonpig->env->storage->undone_jobs_for_ledger($ledger);
      my (@jobs) = grep { $_->job_type eq 'job.on.payment' } @$jobs;
      ok(@jobs == 1, "we made a job on payment!");
    }
  });
};

run_me;
done_testing;

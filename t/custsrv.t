use Test::Routine;
use Test::More;
use Test::Routine::Util;

use t::lib::TestEnv;

with(
  'Moonpig::Test::Role::LedgerTester',
);

use t::lib::Logger;
use Moonpig::Test::Factory qw(do_with_fresh_ledger);

test 'customer service request' => sub {
  my ($self) = @_;
  my $guid;
  my $payload = {
    problem => "everything's catching on fire",
    reason  => "phosphorous excess",
  };

  do_with_fresh_ledger({ c => { template => 'dummy' }}, sub {
    my ($ledger) = @_;
    $guid = $ledger->guid;

    Moonpig->env->file_customer_service_request($ledger, $payload);
  });

  Moonpig->env->process_email_queue;

  my ($delivery) = $self->assert_n_deliveries(1);

  my $data = JSON->new->decode( $delivery->{email}->body_str );
  is_deeply(
    $data,
    { ledger => $guid, payload => $payload },
    "mail contains the body we expect",
  );
};

test 'immediate cust srv req' => sub {
  # Test: (1) getting jobs regardless of type
  #       (2) sending email outside the xact
  my ($self) = @_;
  my $guid;

  do_with_fresh_ledger({ c => { template => 'dummy' }}, sub {
    my ($ledger) = @_;
    $guid = $ledger->guid;

    $ledger->queue_job('test.job.a' => {
      foo => $^T,
      bar => 'serious business',
    });

    $ledger->queue_job('test.job.b' => {
      proc => $$,
      bar  => "..!",
    });

    Moonpig->env->file_customer_service_request($ledger, {});
    Moonpig->env->report_exception([ [ error => "ERROR!!" ] ]);

    # We don't use assert_n_deliveries because we don't want to process the
    # not-yet-committed job queue. -- rjbs, 2012-08-31
    my @deliveries = Moonpig->env->email_sender->deliveries;
    is(@deliveries, 1, "we sent one email immediately");
  });

  Moonpig->env->process_email_queue;

  my @deliveries = Moonpig->env->email_sender->deliveries;
  is(@deliveries, 2, "we sent another mail later");

  my $seen = 0;
  Moonpig->env->storage->iterate_jobs((undef) => sub {
    my ($job) = @_;
    $seen++;
    $job->mark_complete;
  });

  is($seen, 2, "we did two jobs across all types");
};

run_me;
done_testing;

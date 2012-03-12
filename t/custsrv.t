use Test::Routine;
use Test::More;
use Test::Routine::Util;

use t::lib::TestEnv;

with(
  'Moonpig::Test::Role::UsesStorage',
);

use t::lib::Logger;
use Moonpig::Test::Factory qw(do_with_fresh_ledger);

before run_test => sub {
  Moonpig->env->email_sender->clear_deliveries;
};

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

  my @deliveries = Moonpig->env->email_sender->deliveries;
  is(@deliveries, 1, "we sent one email");

  my $data = JSON->new->decode( $deliveries[0]->{email}->body_str );
  is_deeply($data, $payload, "mail contains the body we expect");
};

run_me;
done_testing;

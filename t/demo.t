use Test::Routine;
use Test::More;
use Test::Routine::Util;

with 't::lib::Factory::Ledger';

test "the big exciting demo" => sub {
  my ($self) = @_;

  my $ledger = $self->test_ledger;
  my ($bank, $consumer) = $self->add_bank_and_consumer_to($ledger);

  pass("everything ran to completion without dying");
};

run_me;
done_testing;

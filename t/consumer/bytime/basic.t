use strict;
use warnings;

use Test::Routine;
use Test::More;
use Test::Routine::Util;
use Moonpig::Consumer::ByTime;


with 't::lib::Factory::Ledger';


# use Moonpig::Util -all;

test "constructor" => sub {
  my ($self) = @_;
  plan tests => 1;
  my $c0 = Moonpig::Consumer::ByTime->new({ledger => $self->test_ledger});
  ok($c0);
};

run_me;
done_testing;

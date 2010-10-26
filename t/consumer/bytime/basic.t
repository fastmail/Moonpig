use strict;
use warnings;

use Test::Routine;
use Test::More;
use Test::Routine::Util;
use Moonpig::Consumer::ByTime;

use Try::Tiny;

with 't::lib::Factory::Ledger';


use Moonpig::Util -all;

# todo: warning if no bank
#       suicide
#       create successor
#       hand off to successor

test "constructor" => sub {
  my ($self) = @_;
  plan tests => 2;
  my $ld = $self->test_ledger;

  try {
    # Missing attributes
    Moonpig::Consumer::ByTime->new({ledger => $self->test_ledger});
  } finally {
    ok(@_, "missing attrs");
  };

  my $c = Moonpig::Consumer::ByTime->new({
    ledger => $self->test_ledger,
    cost_amount => dollars(1),
    cost_period => 1,
    min_balance => dollars(0),

  });
  ok($c);
};

test "warnings" => sub {
  my ($self) = @_;
  plan tests => 1;
  my $ld = $self->test_ledger;
  my $b = Moonpig::Bank::Basic->new({ledger => $ld, amount => 1000});
  ok(1);
};

run_me;
done_testing;

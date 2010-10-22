use Test::Routine;
use Test::More;
use Test::Routine::Util;

use Moonpig::CostTree::Basic;
use Moonpig::Charge::Basic;
use Moonpig::Util qw(dollars);

test "the big exciting demo" => sub {
  my ($self) = @_;

  my $tree = Moonpig::CostTree::Basic->new;
  my $charge = Moonpig::Charge::Basic->new({
    description => "for one slice of pie",
    amount      => dollars(8),
  });

  $tree->add_charge_at($charge, 'food.dessert.pie');
  # my $ledger = $self->test_ledger;
  # my ($bank, $consumer) = $self->add_bank_and_consumer_to($ledger);

  pass("everything ran to completion without dying");
};

run_me;
done_testing;

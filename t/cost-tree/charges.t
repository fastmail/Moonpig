use Test::Routine;
use Test::More;
use Test::Routine::Util;

with 't::lib::Factory::Ledger';

use List::Util qw(sum);
use Moonpig::Util qw(class dollars);

test "add some charges to a tree" => sub {
  my ($self) = @_;

  my $ledger = $self->test_ledger;

  my $tree = $ledger->current_journal->cost_tree;

  my @charge_tuples = (
    [ 'food',             'menu viewing surcharge',  dollars(2) ],
    [ 'food.dessert.pie', 'for first slice of pie',  dollars(8) ],
    [ 'drink.soft',       'cup of coffee',           dollars(1) ],
    [ 'food.dessert.pie', 'for second slice of pie', dollars(8) ],
  );

  for my $charge_data (@charge_tuples) {
    my $charge = class('Charge')->new({
      description => $charge_data->[1],
      amount      => $charge_data->[2],
    });

    $tree->add_charge_at($charge, $charge_data->[0]);
  }

  my $expected_total = sum map {; $_->[2] } @charge_tuples;
  is($tree->total_amount, $expected_total, "got the expected total");

  is(
    $tree->path_search('food.dessert')->total_amount,
    dollars(16),
    "total food.dessert as expected",
  );

  my @pie_charges = $tree->path_search('food.dessert.pie')->charges;
  is(@pie_charges, 2, "we made two distinct charges for pie");

  is(
    $tree->path_search('food')->total_amount,
    dollars(18),
   "total food as expected",
  );
};

run_me;
done_testing;

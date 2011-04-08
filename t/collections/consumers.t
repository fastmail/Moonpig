use Test::Routine;
use Test::Routine::Util -all;
use Test::More;
use Test::Fatal;
use Moonpig::Env::Test;
use Moonpig::Util qw(class dollars);

with(
  't::lib::Factory::Ledger',
  't::lib::Role::UsesStorage',
);

use t::lib::ConsumerTemplateSet::Test;

test "create consumer" => sub {
  my ($self) = @_;

  my $ledger = $self->test_ledger;
  my $collection = $ledger->consumer_collection;
  ok($collection->does('Moonpig::Role::Collection::ConsumerExtras'));
  $collection->add_from_template({ template => 'boring',
                                   template_args => { make_active => 1 } });
  is($collection->count, 1, "consumer added");
  my @c = $ledger->consumers;
  is(@c, 1, "exactly one consumer");
  is($c[0]->ledger, $ledger, "ledger set correctly");
  is($c[0]->charge_description, 'boring test charge',
     "template-supplied charge description");
};

run_me;
done_testing;

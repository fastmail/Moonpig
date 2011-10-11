use Test::Routine;
use Test::Routine::Util -all;
use Test::More;
use Test::Fatal;
use Moonpig::Env::Test;
use Moonpig::Util qw(class dollars);
use Scalar::Util qw(refaddr);

use Moonpig::Context::Test -all, '$Context';

with(
  'Moonpig::Test::Role::UsesStorage',
);

use t::lib::ConsumerTemplateSet::Test;
use Moonpig::Test::Factory qw(build_ledger);

test "create consumer" => sub {
  my ($self) = @_;

  my $ledger = build_ledger();
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

  my $consumer_xid = $c[0]->xid;

  my $active = $ledger->active_consumer_for_xid($consumer_xid);

  ok($active, "the consumer xid has an active service");
  is(refaddr($active), refaddr($c[0]), "...and it's the same object");
};

test "route to ad-hoc method" => sub {
  my ($self) = @_;

  my $ledger = build_ledger();
  my $collection = $ledger->consumer_collection;
  my $cons = $collection->resource_request(
    post => { template => 'boring',
              template_args => { make_active => 1 },
            });
  my @c = $ledger->consumers;
  is(@c, 1, "exactly one consumer");
  is($c[0]->ledger, $ledger, "ledger set correctly");
  is($c[0]->charge_description, 'boring test charge',
     "template-supplied charge description");
};

run_me;
done_testing;

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

use namespace::autoclean;

test "check for existence of collection routes" => sub {
  my ($self) = @_;

  my $ledger = $self->test_ledger;
  ok($ledger->route(['consumers']));
  is($ledger->route(['consumers'])->count, 0);
  my $c = $self->add_consumer_to($ledger);
  is($ledger->route(['consumers'])->count, 1);
  is($ledger->route(['consumers', 'guid', $c->guid]), $c);
  is($ledger->route(['consumers', 'count'])->resource_request(get => {}), 1);
};

test "route to get a collection" => sub {
  my ($self) = @_;

  my $ledger = $self->test_ledger;
  Moonpig->env->save_ledger($ledger);

  my $guid = $ledger->guid;

  my ($collection) = Moonpig->env->route(
    [ 'ledger', 'guid', $guid, 'refunds' ],
  );
  ok($collection);

  is($collection->resource_request(get => {}), $collection,
     "collection is a self-getter");
};

test "pages" => sub {
  my ($self) = @_;

  my $ledger = $self->test_ledger;
  Moonpig->env->save_ledger($ledger);
  my @bank;
  for my $i (1..20) {
    my $b = class('Bank')->new({ ledger => $ledger, amount => dollars($i) });
    push @bank, $b;
    $ledger->add_this_bank($b);
  }
  1;

  my ($collection) = $ledger->bank_collection;
  is($collection->count, 20, "20 banks created");
  $collection->default_page_size(7);
  is($collection->route(['pages'])->resource_request(get => {}), 3, "three pages");
  {
    my @pages = map $collection->page({ page => $_}), 1..4;
    is_deeply([ map scalar(@$_), @pages ], [7, 7, 6, 0],
              "three pages of sizes (7,7,6)");
    is(_count_items_in_pages(@pages), 20, "all 20 banks are in the 3 pages");
  }
  {
    my @pages = map $collection->_subroute(['page'])
                        ->resource_request(get => { page => $_}),
                          1..4;
    is_deeply([ map scalar(@$_), @pages ], [7, 7, 6, 0],
              "three pages of sizes (7,7,6)");
    is(_count_items_in_pages(@pages), 20, "all 20 banks are in the 3 pages");
  }
};

sub _count_items_in_pages {
  my %h;
  for my $page (@_) {
    for my $item (@$page) {
      $h{$item->guid} = $item;
    }
  }
  return scalar keys %h;
}

# alternate post_action setting is tested in consumers.t 2011-04-08 MJD
test "add item to a collection" => sub {
  my ($self) = @_;

  my $ledger = $self->test_ledger;
  my $b = class('Bank')->new({ ledger => $ledger, amount => dollars(1) });

  my ($collection) = $ledger->route([ 'banks' ]);
  ok($collection);
  is($collection->count, 0, "no banks yet");
  ok($collection->can('resource_post'), "can post");
  $collection->resource_request(post => { new_item => $b });
  is($collection->count, 1, "added bank via post");
  is($collection->_subroute(['guid', $b->guid]), $b, "bank is available");
};

run_me;
done_testing;

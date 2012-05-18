use Test::Routine;
use Test::Routine::Util -all;
use Test::More;
use Test::Fatal;
use t::lib::TestEnv;
use Moonpig::Util qw(class dollars);

with(
  'Moonpig::Test::Role::UsesStorage',
);
use Moonpig::Test::Factory qw(build_ledger do_with_fresh_ledger);

use namespace::autoclean;

test "check for existence of collection routes" => sub {
  my ($self) = @_;

  do_with_fresh_ledger({}, sub {
    my ($ledger) = @_;
    ok($ledger->route(['consumers']));
    is($ledger->route(['consumers'])->count, 0);
    my $c = $ledger->add_consumer_from_template("dummy");
    is($ledger->route(['consumers'])->count, 1);
    is($ledger->route(['consumers', 'guid', $c->guid]), $c);
    is($ledger->route(['consumers', 'count'])->resource_request(get => {}), 1);
  });
};

test "route to get a collection" => sub {
  my ($self) = @_;

  my $guid = do_with_fresh_ledger({}, sub { return $_[0]->guid });

  Moonpig->env->storage->do_ro(sub {
    my ($collection) = Moonpig->env->route(
      [ 'ledger', 'by-guid', $guid, 'debits' ],
    );
    ok($collection);

    is($collection->resource_request(get => {}), $collection,
       "collection is a self-getter");
  });
};

test "pages" => sub {
  plan skip_all => "rewrite to not use banks; we can't just create banks";
  my ($self) = @_;

  do_with_fresh_ledger({}, sub {
    my ($ledger) = @_;
    my @bank;
    for my $i (1..20) {
      my $credit = $ledger->add_credit(
        class(qw(Credit::Simulated)),
        { amount => dollars($i) },
      );

      my $b = $ledger->add_bank(class('Bank'));
      push @bank, $b;

      $ledger->create_transfer({
        type   => 'test_bank_deposit',
        from   => $credit,
        to     => $b,
        amount => dollars($i),
      });
    }

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
  });
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
  plan skip_all => "rewrite to not use banks; we can't just create banks";
  my ($self) = @_;

  my ($ledger_guid, $b);
  do_with_fresh_ledger({}, sub {
    my ($ledger) = @_;
    $ledger_guid = $ledger->guid;
    my $collection = $ledger->route([ 'banks' ]);
    ok($collection);
    is($collection->count, 0, "no banks yet");
    ok($collection->can('resource_post'), "can post");
    $b = $collection->resource_request(post => { amount => dollars(1) });
    is($collection->count, 1, "added bank via post");
  });

  Moonpig->env->storage->do_with_ledger({ ro => 1 }, $ledger_guid, sub {
    is($_[0]->route([ 'banks' ])->_subroute(['guid', $b->guid]), $b, "bank is available");
  });
};

run_me;
done_testing;

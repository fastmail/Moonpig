use Test::Routine;
use Test::Routine::Util -all;
use Test::More;
use Test::Fatal;

use t::lib::TestEnv;

with(
  'Moonpig::Test::Role::LedgerTester',
);
use Moonpig::Test::Factory qw(do_with_fresh_ledger);

# use Moonpig::Util qw(class days dollars event);

use namespace::autoclean;

use File::Temp qw(tempdir);
use Moonpig::Util qw(class);

test "route to and get a simple resource" => sub {
  my ($self) = @_;

  my ($guid, $ledger);
  my $result = do_with_fresh_ledger({}, sub {
    ($ledger) = @_;
    $guid = $ledger->guid;

    my ($resource) = Moonpig->env->route(
      [ 'ledger', 'by-guid', $guid ],
     );

    return $resource->resource_request(get => {});
  });

  isa_ok(
    $result,
    $ledger->meta->name,
    "...ledger by path",
  );

  is($result->guid, $ledger->guid, "...and the rightly-identified one");
};

test "route to and GET a method on a simple resource" => sub {
  my ($self) = @_;

  my ($guid, $ledger);
  my $result = do_with_fresh_ledger({}, sub {
    ($ledger) = @_;
    $guid = $ledger->guid;

    # XXX: We should not need to use this bogus "gguid" resource, because
    # Ledger does HasGuid, which publishes its "guid" attribute -- but
    # replacing "gguid" with "guid" and (get=>{}) with (get=>()) explodes. --
    # rjbs, 2012-02-10
    my ($resource) = Moonpig->env->route(
      [ 'ledger', 'by-guid', $guid, 'gguid' ],
     );

    return $resource->resource_request(get => {});
  });

  is($result, $guid, "we can get the ledger's guid by routing to it");
};

run_me;
done_testing;

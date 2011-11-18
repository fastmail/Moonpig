use Test::Routine;

use t::lib::TestEnv;

use Carp qw(confess croak);
use Moonpig::Util -all;
use Test::Deep qw(cmp_deeply);
use Test::Fatal;
use Test::More;
use Test::Routine::Util;
use Try::Tiny;

use t::lib::ConsumerTemplateSet::Test;
use Moonpig::Test::Factory qw(build);

test "consumer from template" => sub {
  my ($self) = @_;

  my $stuff = build( c => { template => 'boring' } );
  my $c = $stuff->{c};
  my $ledger = $stuff->{ledger};

  ok(
    $c->does('Moonpig::Role::Consumer::ByTime'),
    "we got a consumer with the roles from the template",
  );

  is(
    $c->charge_description,
    'boring test charge',
    "...and the charge description we expected",
  );

  ok(
    same_object($c, $c->ledger->active_consumer_for_xid( $c->xid )),
    "and things are registered sanely by xid, etc.",
  );
};

run_me;
done_testing;

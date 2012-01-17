use strict;
use warnings;

use Carp qw(confess croak);
use Moonpig::Events::Handler::Noop;
use Moonpig::Util -all;
use Test::More;
use Test::Routine::Util;
use Test::Routine;

use t::lib::TestEnv;

use Moonpig::Test::Factory qw(do_with_fresh_ledger);

use t::lib::TestEnv;

with(
  'Moonpig::Test::Role::UsesStorage',
);

# replace with undef
test has_replacement => sub {
  my ($self) = @_;
  do_with_fresh_ledger({ c => { template => 'dummy', replacement => 'd' },
                         d => { template => 'dummy', },
                         e => { template => 'dummy', }},
    sub {
      my ($ledger) = @_;
      my ($c, $d, $e) = $ledger->get_component(qw(c d e));
      ok($c->has_replacement, "c has replacement");
      is($c->replacement, $d, "c's replacement is d");
      ok(! $d->is_superseded, "d not yet superseded");

      $c->replacement(undef);
      ok(! $c->has_replacement, "c no longer has a replacement");
      ok($d->is_superseded, "d is now superseded");

      $c->replacement($e);
      ok($c->has_replacement, "c has replacement");
      is($c->replacement, $e, "c's replacement is e");
      ok($d->is_superseded, "d still superseded");
      ok(! $e->is_superseded, "e not superseded");
    });
};

# don't let funded C be replaced
# don't let sub-funded C be replaced

# if there's time: supersession tests


run_me;
done_testing;

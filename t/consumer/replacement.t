use strict;
use warnings;

use Carp qw(confess croak);
use Moonpig::Events::Handler::Noop;
use Moonpig::Util -all;
use Test::Fatal;
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
                         d => { template => 'dummy', xid => "test:consumer:c" },
                         e => { template => 'dummy', xid => "test:consumer:c", make_active => 0 }},
    sub {
      my ($ledger) = @_;
      my ($c, $d, $e) = $ledger->get_component(qw(c d e));
      ok($c->has_replacement, "c has replacement");
      is($c->replacement, $d, "c's replacement is d");
      ok(! $d->is_superseded, "d not yet superseded");

      note "eliminating c's replacement";
      $c->replacement(undef);
      ok(! $c->has_replacement, "c no longer has a replacement");
      is($c->replacement, undef, "->replacement returns undef");
      ok($d->is_superseded, "d is now superseded");

      note "setting c's replacement to e";
      $c->replacement($e);
      ok($c->has_replacement, "c has replacement");
      is($c->replacement, $e, "c's replacement is e");
      ok($d->is_superseded, "d still superseded");
      ok(! $e->is_superseded, "e not superseded");
    });
};

# don't let funded C be replaced
# don't let sub-funded C be replaced
test funding => sub {
  like (
    exception {
      do_with_fresh_ledger({ c => { template => 'dummy', replacement => 'd', },
                             d => { template => 'dummy', bank => 10, xid => "test:consumer:c" }},
                             sub {
                               my ($ledger) = @_;
                               my ($c, $d) = $ledger->get_component(qw(c d));
                               $c->replacement(undef);
                             }) },
    qr/replace funded consumer/,
    "replace funded consumer" );

  Moonpig->env->clear_storage;
  is (
    exception {
      do_with_fresh_ledger({ c => { template => 'dummy', replacement => 'd', bank => 10 },
                             d => { template => 'dummy', xid => "test:consumer:c" }},
                             sub {
                               my ($ledger) = @_;
                               my ($c, $d) = $ledger->get_component(qw(c d));
                               $c->replacement(undef);
                             }) },
    undef,
    "replace successor of funded consumer" );

  Moonpig->env->clear_storage;
  like (
    exception {
      do_with_fresh_ledger({ c => { template => 'dummy', replacement => 'd', },
                             d => { template => 'dummy', replacement => 'e',
                                    xid => "test:consumer:c" },
                             e => { template => 'dummy', bank => 10,
                                    xid => "test:consumer:c" }},
                             sub {
                               my ($ledger) = @_;
                               my ($c, $d, $e) = $ledger->get_component(qw(c d e));
                               $c->replacement(undef);
                             }) },
    qr/replace funded consumer/,
    "replace funded consumer" );
};


run_me;
done_testing;

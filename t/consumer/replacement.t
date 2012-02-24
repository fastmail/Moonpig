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

test "replacement chain" => sub {
  my ($self) = @_;
  for my $length (0 .. 5, 0.1) {
    my $x_len = int($length/2) + ($length/2 > int($length/2));
    do_with_fresh_ledger(
      { c => { template => 'quick',
               replacement_plan => [ get => "/consumer-template/quick" ],
               xid => "test:consumer:$length",
             }}, # lasts 2d
      sub {
        my ($ledger) = @_;
        my ($c) = $ledger->get_component('c');
        my $repl = $c->create_replacement_chain(days($length));
        my @chain = $c->replacement_chain();
        is(@chain, $x_len, "replacement chain for $length day(s) has $x_len item(s)");
        my @invoices = $ledger->invoice_collection->all;
        is(@invoices, 1, "still only one invoice");
        my (@charges) = $invoices[0]->all_charges;
        is(@charges, $x_len + 1, "each consumer charged the invoice");
        is($invoices[0]->total_amount, dollars(100 * ($x_len + 1)), "total amount");
      });
  }
};

run_me;
done_testing;

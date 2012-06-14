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
               xid => "test:consumer:$length",
             }}, # lasts 2d
      sub {
        my ($ledger) = @_;
        my ($c) = $ledger->get_component('c');
        my $repl = $c->_adjust_replacement_chain(days($length));
        my @chain = $c->replacement_chain();
        is(@chain, $x_len, "replacement chain for $length day(s) has $x_len item(s)");
        my @invoices = $ledger->invoice_collection->all;
        is(@invoices, 1, "still only one invoice");
        my (@charges) = $invoices[0]->all_charges;
        is(@charges, $x_len + 1, "each consumer charged the invoice");
        is($invoices[0]->total_amount, dollars(100 * ($x_len + 1)), "total amount");
      });
  }

  do_with_fresh_ledger(
    { c => { template => 'quick',
             xid => "test:consumer:ick",
             replacement_chain_duration => days(5),
           }},
    sub {
      my ($ledger) = @_;
      my @chain = $ledger->get_component('c')->replacement_chain;
      is(@chain, 3, "BUILD-time replacement_chain_duration works");
    });

  do_with_fresh_ledger(
    { c => { template => 'quick',
             xid => "test:consumer:poop",
             minimum_chain_duration => days(7),
           }},
    sub {
      my ($ledger) = @_;
      my @chain = $ledger->get_component('c')->replacement_chain;
      is(@chain, 3, "BUILD-time replacement_chain_duration works");
    });

  do_with_fresh_ledger(
    { c => { template => 'quick',
             xid => "test:consumer:stew",
             replacement_chain_duration => days(5),
           }},
    sub {
      my ($ledger) = @_;
      my ($c) = $ledger->get_component('c');
      for my $length (1, 2, 4, 4, 3, 0, 2) {
        my $consumers = $length == 1 ? "consumer" : "consumers";
        $c->_adjust_replacement_chain(days(2 * $length));
        my @chain = $c->replacement_chain;
        is(@chain, $length, "adjusted length of replacement chain to $length $consumers");
      }
    });

  do_with_fresh_ledger(
    { c => { template => 'quick',
             xid => "test:consumer:soup",
             minimum_chain_duration => days(7),
           }},
    sub {
      my ($ledger) = @_;
      my ($c) = $ledger->get_component('c');
      for my $length (1, 2, 4, 4, 3, 0, 2) {
        my $consumers = $length == 1 ? "consumer" : "consumers";
        $c->_adjust_replacement_chain(days(2 * $length));
        my @chain = $c->replacement_chain;
        is(@chain, $length, "adjusted length of replacement chain to $length $consumers");
      }
    });
};

test "replacement chain to zero" => sub {
  my ($self) = @_;

  do_with_fresh_ledger(
    { c => { template => 'quick',
             xid => "test:consumer:xyz",
           }}, # lasts 2d
    sub {
      my ($ledger) = @_;
      my ($c) = $ledger->get_component('c');
      my $repl = $c->adjust_replacement_chain({ chain_duration => 0 });
      ok("lived");
    },
  );
};

sub make_charges {
  my ($ledger, %args) = @_;
  my @consumers = @{$args{consumers}};
  my $amount = $args{amount} || dollars(1);
  my $description = $args{description} || "some charge";

  for my $c (@consumers) {
    $c->charge_current_invoice({
      description => $description,
      amount      => $amount,
    });
  }
  return $ledger->current_invoice;
}

test "superseded consumers abandon unpaid charges" => sub {
  do_with_fresh_ledger(
    { c => { template => 'dummy', replacement => 'd' },
      d => { template => 'dummy', replacement => 'e', xid => "test:consumer:c" },
      e => { template => 'dummy',                     xid => "test:consumer:c", make_active => 0 }
    },
    sub {
      my ($ledger) = @_;
      my ($c, $d, $e) = $ledger->get_component(qw(c d e));
      my $i1 = make_charges($ledger, consumers => [ $c, $d, $e ], amount => dollars(5));
      $i1->mark_closed;

      # This is a hack.  We should be paying normally. -- rjbs, 2012-05-21
      $i1->mark_paid;
      $_->__set_executed_at( Moonpig->env->now ) for $i1->all_charges;

      is($i1->total_amount, dollars(15));

      my $i2 = make_charges($ledger, consumers => [ $c, $d, $e ], amount => dollars(10));
      $i2->mark_closed;
      is($i2->total_amount, dollars(30));

      my $dd = $ledger->add_consumer_from_template(
        "dummy",
        { xid => "test:consumer:c" });

      $c->replacement($dd);

      ok($d->is_superseded, "d is superseded by dd");
      ok($e->is_superseded, "e is also superseded");
      is($i1->total_amount, dollars(15), "i1 amount didn't change");
      is($i2->total_amount, dollars(10), "i2 amount omits both abandoned charges");
    });
};

test "replacement chain loops" => sub {
  plan tests => 16;
  for my $test (qw(cc cd ce cf
                   dc dd de df
                   ec ed ee ef
                   fc fd fe ff)) {
    my $bad = { cc => 1, dd => 1, ee => 1,
                dc => 1, ed => 1, ec => 1,
                ff => 1 };
    do_with_fresh_ledger(
      { c => { template => 'dummy', replacement => 'd', make_active => 0 },
        d => { template => 'dummy', replacement => 'e', make_active => 0 },
        e => { template => 'dummy',                     make_active => 0 },
        f => { template => 'dummy',                     make_active => 0 },
       },
      sub {
        my ($ledger) = @_;
        my ($x1, $x2) = split //, $test;
        my ($c1, $c2) = map $ledger->get_component($_), $x1, $x2;
        my $result = exception { $c1->replacement($c2) };
        if ($bad->{$test}) {
          like($result, qr/replacement loop/,
               "caught attempt to make replacement loop via $x1 and $x2");
        } else {
          is($result, undef, "OK to make replacement of $x1 be $x2");
        }
      });
  }
};

run_me;
done_testing;

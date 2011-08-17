#!/usr/bin/env perl
use Test::Routine;
use Test::Routine::Util -all;

use Test::Fatal;
use Test::More;

use Moonpig::Context::Test -all, '$Context';

with(
  't::lib::Role::UsesStorage',
);

use t::lib::Logger '$Logger';
use t::lib::Factory qw(build);

use Moonpig::Env::Test;

use Moonpig::Events::Handler::Code;

use Data::GUID qw(guid_string);
use List::Util qw(sum);
use Moonpig::Util qw(class days dollars event);

use namespace::autoclean;

sub random_xid {
  return 'urn:uuid:' . guid_string;
}

sub _test_ledgers_and_xids {
  my ($self) = @_;

  my (%ledger, %xid);

  for my $key (qw(1 2)) {
    $xid{ $key }    = $self->random_xid;
    $ledger{ $key } = build(
        consumer => {
            class => class('Consumer::Dummy'),
            xid   => $xid{$key},
            make_active        => 1,
            replacement_mri    => Moonpig::URI->nothing,
        })->{ledger};


    Moonpig->env->save_ledger($ledger{$key});
  }

  return( \%ledger, \%xid );
}

test "global xid lookup" => sub {
  my ($self) = @_;

  my ($ledger, $xid) = $self->_test_ledgers_and_xids;

  for my $id (1, 2) {
    my $got_ledger = Moonpig->env->storage->retrieve_ledger_for_xid($xid->{$id});

    isa_ok(
      $got_ledger,
      ref($ledger->{$id}),
      "ledger for xid $id"
    );

    is(
      $got_ledger->guid,
      $ledger->{$id}->guid,
      "xid $id -> ledger $id",
    );
  }
};

test "one-ledger-per-xid safety" => sub {
  my ($self) = @_;

  my $Ledger = class('Ledger');

  my ($ledger, $xid) = $self->_test_ledgers_and_xids;

  my $err = exception {
    $ledger->{1}->add_consumer(
      class(qw(Consumer::Dummy)),
      {
        xid                => $xid->{2},
        make_active        => 1,

        replacement_mri    => Moonpig::URI->nothing,
      },
    );

    Moonpig->env->save_ledger($ledger->{1});
  };

  ok($err, "we can't register 1 id with 2 ledgers");

  {
    local $TODO = "err msg currently provided by SQLite";
    like($err, qr/already registered/, "can't register 1 xid with 2 ledgers");
  }
};

test "registered abandoned xid" => sub {
  my ($self) = @_;

  my $Ledger = class('Ledger');

  my ($ledger, $xid) = $self->_test_ledgers_and_xids;

  # first, ensure that both X-1 and X-2 are taken by L-1 and L-2
  for (1, 2) {
    is(
      Moonpig->env->storage->retrieve_ledger_for_xid($xid->{$_})->guid,
      $ledger->{$_}->guid,
      "xid $_ -> ledger $_",
    );
  }

  my $consumer = $ledger->{1}->active_consumer_for_xid($xid->{1});
  $consumer->handle_event(event('terminate'));

  Moonpig->env->save_ledger($ledger->{1});

  # now, X-1 should go nowhere, but X-2 is still taken by L-2
  is(
    Moonpig->env->storage->retrieve_ledger_for_xid($xid->{1}),
    undef,
    "xid 1 -> (undef)",
  );

  is(
    Moonpig->env->storage->retrieve_ledger_for_xid($xid->{2})->guid,
    $ledger->{2}->guid,
    "xid 2 -> ledger 2",
  );

  # Since X-1 is unclaimed, we can give it to L-2
  $ledger->{2}->add_consumer(
    class(qw(Consumer::Dummy)),
    {
      xid                => $xid->{1},
      make_active        => 1,

      replacement_mri    => Moonpig::URI->nothing,
    },
  );

  Moonpig->env->save_ledger($ledger->{2});

  # Now make sure that both X-1 and X-2 are on L-2
  for (1, 2) {
    my $got_ledger = Moonpig->env->storage->retrieve_ledger_for_xid($xid->{$_});

    is(
      $got_ledger->guid,
      $ledger->{2}->guid,
      "xid $_ -> ledger 2",
    );
  }

};

run_me;
done_testing;

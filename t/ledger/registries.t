#!/usr/bin/env perl
use Test::Routine;
use Test::Routine::Util -all;

use Test::Fatal;
use Test::More;

with(
  't::lib::Factory::Ledger',
);

use t::lib::Logger '$Logger';

use Moonpig::Env::Test;

use Moonpig::Events::Handler::Code;

use Data::GUID qw(guid_string);
use List::Util qw(sum);
use Moonpig::Util qw(class days dollars event);

use namespace::autoclean;

sub random_xid {
  return 'urn:uuid:' . guid_string;
}

test "global ledger registry" => sub {
  my ($self) = @_;

  my $ledger_guid;
  my $consumer_guid;

  {
    my $ledger = $self->test_ledger;

    $ledger_guid = $ledger->guid;

    my $consumer = $ledger->add_consumer(
      class(qw(Consumer::Dummy)),
      {
        xid                => $self->random_xid,
        make_active        => 1,

        charge_path_prefix => '',
        old_age            => 1,
        replacement_mri    => Moonpig::URI->nothing,
      },
    );

    $consumer_guid = $consumer->guid;
  }

  my $ledger = class('Ledger')->for_guid($ledger_guid);
  
  isa_ok($ledger, class('Ledger'));
  is($ledger->guid, $ledger_guid, "we got back the right ledger");

  my @consumers = $ledger->consumers;
  is(@consumers, 1, "we got back the ledger with 1 consumer");

  is($consumers[0]->guid, $consumer_guid, "...and it's the right consumer");
};

sub _test_ledgers_and_xids {
  my ($self) = @_;

  my (%ledger, %xid);

  for my $key (qw(1 2)) {
    $ledger{ $key } = $self->test_ledger;
    $xid{ $key }    = $self->random_xid;

    $ledger{$key}->add_consumer(
      class(qw(Consumer::Dummy)),
      {
        xid                => $xid{$key},
        make_active        => 1,

        charge_path_prefix => '',
        old_age            => 1,
        replacement_mri    => Moonpig::URI->nothing,
      },
    );
  }

  return( \%ledger, \%xid );
}

test "global xid lookup" => sub {
  my ($self) = @_;

  my $Ledger = class('Ledger');

  my ($ledger, $xid) = $self->_test_ledgers_and_xids;

  for (1, 2) {
    is(
      $Ledger->for_xid($xid->{$_})->guid,
      $ledger->{$_}->guid,
      "xid $_ -> ledger $_",
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

        charge_path_prefix => '',
        old_age            => 1,
        replacement_mri    => Moonpig::URI->nothing,
      },
    );
  };

  like($err, qr/already registered/, "can't register 1 xid with 2 ledgers");
};

test "registered abandoned xid" => sub {
  my ($self) = @_;

  my $Ledger = class('Ledger');

  my ($ledger, $xid) = $self->_test_ledgers_and_xids;

  # first, ensure that both X-1 and X-2 are taken by L-1 and L-2
  for (1, 2) {
    is(
      $Ledger->for_xid($xid->{$_})->guid,
      $ledger->{$_}->guid,
      "xid $_ -> ledger $_",
    );
  }

  my ($consumer) = $ledger->{1}->active_consumers_for_xid($xid->{1});
  $consumer->terminate_service;

  # now, X-1 should go nowhere, but X-2 is still taken by L-2
  is(
    $Ledger->for_xid($xid->{1}),
    undef,
    "xid 1 -> (undef)",
  );
  is(
    $Ledger->for_xid($xid->{2})->guid,
    $ledger->{2}->guid,
    "xid 2 -> ledger 2",
  );

  # Since X-1 is unclaimed, we can give it to L-2
  $ledger->{2}->add_consumer(
    class(qw(Consumer::Dummy)),
    {
      xid                => $xid->{1},
      make_active        => 1,

      charge_path_prefix => '',
      old_age            => 1,
      replacement_mri    => Moonpig::URI->nothing,
    },
  );

  # Now make sure that both X-1 and X-2 are on L-2
  for (1, 2) {
    is(
      $Ledger->for_xid($xid->{$_})->guid,
      $ledger->{2}->guid,
      "xid $_ -> ledger 2",
    );
  }

};

run_me;
done_testing;

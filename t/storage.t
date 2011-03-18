#!/usr/bin/env perl
use Test::Routine;
use Test::Routine::Util -all;
use Test::More;

with(
  't::lib::Factory::Ledger',
);

use t::lib::Logger '$Logger';

use Moonpig::Env::Test;
use Moonpig::Storage;

use Data::GUID qw(guid_string);

use t::lib::ConsumerTemplateSet::Demo;

use namespace::autoclean;

test "try to store stuff" => sub {
  my $xid = 'yoyodyne://account/' . guid_string;

  my $ledger = __PACKAGE__->test_ledger;

  my $consumer = $ledger->add_consumer_from_template(
    'demo-service',
    {
      xid                => $xid,
      make_active        => 1,
    },
  );

  Moonpig::Storage->store_ledger($ledger);

  my $retr_ledger = Moonpig::Storage->retrieve_ledger($ledger->guid);

  # diag explain $retr_ledger;

  pass('we lived');
};

run_me;
done_testing;

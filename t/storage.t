#!/usr/bin/env perl
use Test::Routine;
use Test::Routine::Util -all;
use Test::More;

with(
  't::lib::Factory::Ledger',
  't::lib::Role::UsesStorage',
);

use t::lib::Logger '$Logger';

use Moonpig::Env::Test;

use Data::GUID qw(guid_string);
use Path::Class;

use t::lib::ConsumerTemplateSet::Demo;

use namespace::autoclean;

test "store and retrieve" => sub {
  my ($self) = @_;

  my $pid = fork;
  Carp::croak("error forking") unless defined $pid;

  my $xid = 'yoyodyne://account/' . guid_string;

  if ($pid) {
    wait;
    if ($?) {
      my %waitpid = (
        status => $?,
        exit   => $? >> 8,
        signal => $? & 127,
        core   => $? & 128,
      );
      die("error with child: " . Dumper(\%waitpid));
    }
  } else {
    my $ledger = __PACKAGE__->test_ledger;

    my $consumer = $ledger->add_consumer_from_template(
      'demo-service',
      {
        xid                => $xid,
        make_active        => 1,
      },
    );

    Moonpig->env->save_ledger($ledger);

    exit(0);
  }

  my @guids = Moonpig->env->storage->ledger_guids;

  is(@guids, 1, "we have stored one guid");

  my $ledger = Moonpig->env->storage->retrieve_ledger_for_guid($guids[0]);

  my $consumer = $ledger->active_consumer_for_xid($xid);
  # diag explain $retr_ledger;

  pass('we lived');
};

run_me;
done_testing;

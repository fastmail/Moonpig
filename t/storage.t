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
use File::Temp qw(tempdir);
use Path::Class;

use t::lib::ConsumerTemplateSet::Demo;

use namespace::autoclean;

has tempdir => (
  is  => 'ro',
  isa => 'Str',
  default => sub { tempdir(CLEANUP => 1 ) },
);

test "store and retrieve" => sub {
  my ($self) = @_;

  local $ENV{MOONPIG_STORAGE_ROOT} = $self->tempdir;

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

    Moonpig::Storage->store_ledger($ledger);

    Test::Builder->new->no_ending(1);
    exit(0);
  }

  my @files = grep { -f } dir($self->tempdir)->children;

  Carp::croak("found too many files!"), note explain \@files if @files > 1;

  my ($guid) = $files[0] =~ m{/([^/]+)\.sqlite\z};

  my $ledger = Moonpig::Storage->retrieve_ledger($guid);

  my $consumer = $ledger->active_consumer_for_xid($xid);
  # diag explain $retr_ledger;

  pass('we lived');
};

run_me;
done_testing;

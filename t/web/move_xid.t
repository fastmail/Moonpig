
use JSON;
use Moonpig::App::Ob::Dumper qw();
use Moonpig::Env::Test;
use Moonpig::UserAgent;
use Moonpig::Util qw(days dollars);
use Moonpig::Web::App;
use Plack::Test;
use Test::Deep qw(cmp_deeply re ignore superhashof);
use Test::Fatal;
use Test::More;
use Test::Routine;
use Test::Routine::Util '-all';

use lib 'eg/fauxbox/lib';
use Fauxbox::Moonpig::TemplateSet;

use Moonpig::Context::Test -all, '$Context';

use strict;

with ('t::lib::Role::UsesStorage');

my $ua  = Moonpig::UserAgent->new({ base_uri => "http://localhost:5001" });
my $app = Moonpig::Web::App->app;

my $u_xid = 'test:username:testuser';
my $a_xid = "test:account:1";

my $guid_re = re('^[A-F0-9]{8}(-[A-F0-9]{4}){3}-[A-F0-9]{12}$');
my $date_re = re('^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d$');

sub setup_account {
  my ($self) = @_;
  my %rv;

  my $signup_info =
    { name => "Fred Flooney",
      email_addresses => [ 'testuser@example.com' ],
      address_lines   => [ '1313 Mockingbird Ln.' ],
      city            => 'Wagstaff',
      country         => 'USA',
      consumers => {
        $u_xid => {
          template => 'username'
         },
      },
    };

  test_psgi app => $app,
    client => sub {
      my $cb = shift;
      $ua->set_test_callback($cb);

      $rv{ledger_guid} = do {
        my $result = $ua->mp_post('/ledgers', $signup_info);
        cmp_deeply(
          $result,
          superhashof({
            active_xids => { $u_xid => superhashof({ guid => $guid_re }) },
            guid        => $guid_re
          }),
          "Created ledger"
        );
        $result->{guid};
      };

      $rv{ledger_path} = sprintf "/ledger/by-guid/%s", $rv{ledger_guid};

      $rv{account_guid} = do {
        my $account_info = {
          template      => 'fauxboxtest',
          template_args => {
            xid         => $a_xid,
            make_active => 1,
          },
        };

        my $result = $ua->mp_post("$rv{ledger_path}/consumers",
                                  $account_info);
        cmp_deeply(
          $result,
          superhashof({ guid => $guid_re }),
          "added consumer",
        );

        $result;
      };
    };

  return \%rv;
}

sub check_xid {
  my ($self, $xid, $here, $not_here) = @_;
  # $here and $not_here are guids of ledgers in which the specified $xid
  # should be found, and should NOT be found, respectively.
  # $not_here may be undef, in which case those tests are skipped.

  isnt($ua->mp_get("/ledger/by-guid/$here/consumers/active/$xid"), undef,
       "$xid consumer in expected ledger");
  is($ua->mp_get("/ledger/by-xid/$xid")->{guid}, $here, "ledger for $xid as expected");
  if (defined $not_here) {
    is($ua->mp_get("/ledger/by-guid/$not_here/consumers/active/$xid"), undef,
       "$xid absent from other ledger");
  }
}

test split => sub {
  my ($self) = @_;

  my $v1 = $self->setup_account;
  my $ledger_a_guid = $v1->{ledger_guid};
  my $cons_a_guid   = $v1->{account_guid};
  my $ledger_path   = $v1->{ledger_path};

  $self->check_xid($a_xid, $ledger_a_guid);

  note "Splitting responsibility for $a_xid to new ledger\n";
  my $result = $ua->mp_post(
    "$ledger_path/split",
    {
      xid => $a_xid,
      contact => {
        name => "Mr. Hand",
        email_addresses => [ 'mrhand@example.com' ],
        address_lines   => [ '221B Baker St.' ],
        city            => 'London',
        country         => 'UK',
      }
    });
  ok($result, "web service returns new consumer $result");
  my $ledger_b_guid = $ua->mp_get("/ledger/by-xid/$a_xid")->{guid};
  isnt($ledger_b_guid, $ledger_a_guid, "$a_xid is in a different ledger");
  $self->check_xid($a_xid, $ledger_b_guid, $ledger_a_guid);
  # TODO: check to make sure the new ledger has the right contact info

  note "Splitting nonexistent sservice should fail";
  isnt( exception {
    $ua->mp_post(
      "/ledger/by-guid/$ledger_a_guid/split",
      {
        xid => $a_xid,
        contact => {
          name => "Mr. Hand",
          email_addresses => [ 'mrhand@example.com' ],
          address_lines   => [ '221B Baker St.' ],
          city            => 'London',
          country         => 'UK',
        }
      }) },
    undef,
    "properly refusing to split out unmanaged xid");
};

test handoff => sub {
  my ($self) = @_;
  my ($ledger, $consumer);

  my $v1 = $self->setup_account;
  my $ledger_a_guid = $v1->{ledger_guid};
  my $cons_a_guid = $v1->{account_guid};
  my $result;

  $self->check_xid($a_xid, $ledger_a_guid);
  my $ledger_b_guid = do {
    my $result = $ua->mp_post(
      '/ledgers',
      { name => "Ted 'Theodore' Logan",
        email_addresses => [ 'ttl@example.com' ],
        address_lines   => [ '1 W. Eastside Cir.' ],
        city            => 'San Dimas',
        state           => 'CA',
        country         => 'USA',
      });
    $result->{guid};
  };

  note "Transferring responsibility for $a_xid to ledger $ledger_b_guid\n";
  $result = $ua->mp_post(
    "/ledger/by-guid/$ledger_a_guid/handoff",
    {
      xid => $a_xid,
      target_ledger => $ledger_b_guid,
    });
  ok($result, "web service returns new consumer $result");
  $self->check_xid($a_xid, $ledger_b_guid, $ledger_a_guid);

  note "Transferring responsibility back";
  $result = $ua->mp_post(
    "/ledger/by-guid/$ledger_b_guid/handoff",
    {
      xid => $a_xid,
      target_ledger => $ledger_a_guid,
    });
  ok($result, "web service returns new consumer $result");
  $self->check_xid($a_xid, $ledger_a_guid, $ledger_b_guid);

  note "Transferring responsibility incorrectly";
  isnt( exception {
    $ua->mp_post(
      "/ledger/by-guid/$ledger_b_guid/handoff",
      {
        xid => $a_xid,
        target_ledger => $ledger_a_guid,
      }) },
    undef,
    "properly refusing to transfer management of unmanaged xid");
};

sub pause {
  print STDERR "Pausing... ";
  my $x = <STDIN>;
}

sub Dump {
  my ($what) = @_;
  my $text = Moonpig::App::Ob::Dumper::Dump($what);
  $text =~ s/^/# /gm;
  warn $text;
}

run_me;
done_testing;

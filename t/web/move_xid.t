
use JSON;
use Moonpig::App::Ob::Dumper qw();
use Moonpig::Env::Test;
use Moonpig::UserAgent;
use Moonpig::Util qw(days dollars);
use Moonpig::Web::App;
use Plack::Test;
use Test::Deep qw(cmp_deeply re);
use Test::Fatal;
use Test::More;
use Test::Routine;
use Test::Routine::Util '-all';

use lib 'eg/fauxbox/lib';
use Fauxbox::Moonpig::TemplateSet;

use strict;

with ('t::lib::Role::UsesStorage');

my $ua = Moonpig::UserAgent->new({ base_uri => "http://localhost:5001" });
my $json = JSON->new;
my $app = Moonpig::Web::App->app;

my $x_username = 'testuser';
my $u_xid = username_xid($x_username);
my $a_xid = "test:account:1";
my $ledger_path;

my $guid_re = re('^[A-F0-9]{8}(-[A-F0-9]{4}){3}-[A-F0-9]{12}$');
my $date_re = re('^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d$');

my $price = dollars(20);

sub setup_account {
  my ($self) = @_;
  my %rv;

  my $signup_info =
    { name => "Fred Flooney",
      email_addresses => [ 'testuser@example.com' ],
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
        cmp_deeply($result,
                   { value =>
                       {
                         active_xids => { $u_xid => $guid_re },
                         guid => $guid_re
                        } } );
        $result->{value}{guid};
      };
      $ledger_path = sprintf "/ledger/guid/%s", $rv{ledger_guid};

      $rv{account_guid} = do {
        my $account_info = {
          template      => 'fauxboxtest',
          template_args => {
            xid         => $a_xid,
            make_active => 1,
          },
        };

        my $result = $ua->mp_post("$ledger_path/consumers",
                                  $account_info);
        cmp_deeply($result, { value => $guid_re });

        $result->{value};
      };
    };

  return \%rv;
}

test split => sub {
  my ($self) = @_;
  my ($ledger, $consumer);

  my $v1 = $self->setup_account;
  my $ledger_a_guid = $v1->{ledger_guid};
  my $cons_a_guid = $v1->{account_guid};
  isnt($ua->mp_get("/ledger/guid/$ledger_a_guid"), undef, "found original ledger");
  isnt($ua->mp_get("$ledger_path/consumers/active/$a_xid"), undef, "$a_xid in original ledger");
  is($ua->mp_get("/ledger/xid/$a_xid")->{value}{guid}, $ledger_a_guid, "$a_xid in original ledger");

  my $new_consumer = $ua->mp_post(
    "$ledger_path/split",
    {
      xid => $a_xid,
      contact_name => "Bill S. Preston",
      contact_email_addresses => [ "bspesq\@example.com" ],
    });
  ok($new_consumer);
  my $new_consumer_guid = $new_consumer->{value};

  is($ua->mp_get("$ledger_path/consumers/active/$a_xid"), undef,
     "$a_xid no longer in original ledger");
  my $ledger_b_guid = $ua->mp_get("/ledger/xid/$a_xid")->{value}{guid};
  isnt($ledger_b_guid, $ledger_a_guid, "$a_xid no longer in original ledger");
  isnt($ua->mp_get("/ledger/guid/$ledger_b_guid/consumers/active/$a_xid"), undef,
       "$a_xid found in new ledger");
};

sub elapse {
  my ($self, $days) = @_;
  while ($days >= 1) {
    $ua->mp_get("/advance-clock/86400");
    $ua->mp_post("$ledger_path/heartbeat", {});
    $days--;
  }
  if ($days > 0) {
    $ua->mp_get(sprintf "/advance-clock/%d", $days * 86400);
    $ua->mp_post("$ledger_path/heartbeat", {});
  }
}

sub now {
  my ($self) = @_;
  my $res = $ua->mp_get("/time");
  return $res->{now};
}

sub username_xid { "test:username:$_[0]" }

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

warn "################################################################\n";
run_me;
done_testing;

use Test::Routine;
use Test::Routine::Util '-all';

use JSON;
use Moonpig::App::Ob::Dumper qw();
use Moonpig::Env::Test;
use Moonpig::UserAgent;
use Moonpig::Util qw(days dollars);
use Moonpig::Web::App;
use Plack::Test;
use Test::Deep qw(cmp_deeply re bool);
use Test::More;

use lib 'eg/fauxbox/lib';
use Fauxbox::Moonpig::TemplateSet;

with ('t::lib::Role::UsesStorage');

my $ua = Moonpig::UserAgent->new({ base_uri => "http://localhost:5001" });
my $json = JSON->new;
my $app = Moonpig::Web::App->app;

my $x_username = 'testuser';
my $u_xid = username_xid($x_username);
my $a_xid = "test:account:1";
my $ledger_path = "/ledger/xid/$u_xid";

my $guid_re = re('^[A-F0-9]{8}(-[A-F0-9]{4}){3}-[A-F0-9]{12}$');
my $date_re = re('^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d$');

my $price = dollars(20);

sub setup_account {
  my ($self) = @_;
  my %rv;

  my $signup_info =
    { name => "Fred Flooney",
      email_addresses => [ 'textuser@example.com' ],
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
        cmp_deeply($result, { value => $guid_re }, "ledger has one consumer");

        $result->{value};
      };

      $self->elapse(0.5);

      my $invoices = $ua->mp_get("$ledger_path/invoices/unpaid");

      cmp_deeply(
        $invoices,
        {
          value => [
            {
              date => $date_re,
              guid => $guid_re,
              is_paid   => bool(0),
              is_closed => bool(1),
              total_amount => dollars(20),
            },
          ],
        },
        "there is one unpaid invoice -- what we expect",
      );

      my $invoice_guid = $invoices->{value}[0]{guid};
      my $invoice = $ua->mp_get("$ledger_path/invoices/guid/$invoice_guid");
      cmp_deeply($invoice,
                 { value =>
                     { date => $date_re,
                       guid => $invoice_guid,
                       is_closed => $JSON::XS::true,
                       is_paid => $JSON::XS::false,
                       total_amount => $price,
                     } } );
  };

  return \%rv;
}

test clobber_replacement => sub {
  my ($self) = @_;
  my ($ledger, $consumer);

  my $v1 = $self->setup_account;
  my $credit = $ua->mp_post(
    "$ledger_path/credits/accept_payment",
    {
      amount => $price,
      type => 'Simulated',
    });
  $self->elapse(3);

  $ledger = Moonpig->env->storage
    ->retrieve_ledger_for_guid($v1->{ledger_guid});
  $consumer = $ledger->active_consumer_for_xid($a_xid);
  my $consumer_guid = $consumer->guid;

  ok($consumer->replacement, "account has a replacement");
  ok($consumer->has_replacement, "account has a replacement (predicate)");
  isnt($consumer->replacement->guid, $consumer->guid,
       "replacement is different");
  ok($consumer->replacement->does("Moonpig::Role::Consumer::ByTime"),
       "replacement is another ByTime");
  ok(! $consumer->replacement->bank, "replacement is unfunded");
  ok(! $consumer->replacement->is_expired, "replacement has not yet expired");

  $ua->mp_post("$ledger_path/consumers/active/$a_xid/cancel", {});
  $ledger = Moonpig->env->storage
    ->retrieve_ledger_for_guid($v1->{ledger_guid});
  $consumer = $ledger->consumer_collection
    ->find_by_guid({ guid => $consumer_guid });

  ok($consumer->replacement->is_expired, "replacement has expired");
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

test cancel_early => sub {
  my ($self) = @_;
  my ($ledger, $consumer);

  my $v1 = $self->setup_account;
  my $credit = $ua->mp_post(
    "$ledger_path/credits/accept_payment",
    {
      amount => $price,
      type => 'Simulated',
    });
  $self->elapse(1);

  {
    $ledger = Moonpig->env->storage
      ->retrieve_ledger_for_guid($v1->{ledger_guid});
    $consumer = $ledger->consumer_collection->find_by_xid({ xid => $a_xid });
    ok(! $consumer->replacement, "account has no replacement yet");
    isnt($consumer->replacement_mri->as_string, "moonpig://nothing",
         "replacement MRI is not 'nothing'");
  }

  $ua->mp_post("$ledger_path/consumers/xid/$a_xid/cancel", {});

  {
    $ledger = Moonpig->env->storage
      ->retrieve_ledger_for_guid($v1->{ledger_guid});
    $consumer = $ledger->consumer_collection->find_by_xid({ xid => $a_xid });
    is($consumer->replacement_mri->as_string, "moonpig://nothing",
       "replacement MRI has been changed to 'nothing'");
  }
};

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

run_me;
done_testing;

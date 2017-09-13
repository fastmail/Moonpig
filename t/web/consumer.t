use Test::Routine;
use Test::Routine::Util '-all';

use JSON;
use Moonpig::App::Ob::Dumper qw();
use t::lib::TestEnv;
use Moonpig::UserAgent;
use Moonpig::Util qw(days dollars);
use Moonpig::Web::App;
use Plack::Test;
use Test::Deep qw(cmp_deeply re bool superhashof ignore);
use Test::More;

use lib 'eg/fauxbox/lib';
use Fauxbox::Moonpig::TemplateSet;

with ('Moonpig::Test::Role::LedgerTester');

my $ua = Moonpig::UserAgent->new({ base_uri => "http://localhost:5001" });
my $json = JSON->new;
my $app = Moonpig::Web::App->app;

my $x_username = 'testuser';
my $u_xid = username_xid($x_username);
my $a_xid = "test:account:1";
my $ledger_path = "/ledger/by-xid/$u_xid";

my $guid_re = re('^[A-F0-9]{8}(-[A-F0-9]{4}){3}-[A-F0-9]{12}$');
my $date_re = re('^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d$');

my $price = dollars(20);

sub setup_account {
  my ($self) = @_;
  my %rv;

  my $signup_info =
    {
      contact => {
        first_name => "Fred",
        last_name  => "Flooney",
        phone_book => { home => '12345678' },
        email_addresses => [ 'textuser@example.com' ],
        address_lines   => [ '1313 Mockingbird Ln.' ],
        city            => 'Wagstaff',
        country         => 'USA',
      },
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
            guid => $guid_re
          }),
        );
        $result->{guid};
      };

      Moonpig->env->storage->do_rw(sub {
        my $ledger = Moonpig->env->storage
          ->retrieve_ledger_for_guid($rv{ledger_guid});

        my @abandoned = grep {;
          $_->is_abandoned }
        $ledger->invoice_collection->all;
        is(
          @abandoned,
          0,
          'no abandoned invoices after setting up a new ledger'
        );
      });

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
        cmp_deeply(
          $result,
          superhashof({ guid => $guid_re }),
          "ledger has one consumer",
        );

        $result;
      };

      $self->elapse(0.5);

      $self->assert_n_deliveries(1, "invoice");

      my $invoices = $ua->mp_get("$ledger_path/invoices/payable")->{items};

      cmp_deeply(
        $invoices,
        [
          superhashof({
            created_at => $date_re,
            guid => $guid_re,
            paid_at   => bool(0),
            closed_at => bool(1),
            total_amount => $price,
            charges => ignore(),
          }),
        ],
        "there is one unpaid invoice -- what we expect",
      );

      my $invoice_guid = $invoices->[0]{guid};
      my $invoice = $ua->mp_get("$ledger_path/invoices/guid/$invoice_guid");
      cmp_deeply(
        $invoice,
        superhashof({
          created_at => $date_re,
          guid => $invoice_guid,
          closed_at => bool(1),
          paid_at => bool(0),
          total_amount => $price,
          charges => ignore(),
        }),
      );
  };

  return \%rv;
}

test clobber_replacement => sub {
  my ($self) = @_;
  my ($ledger, $consumer);

  my $v1 = $self->setup_account;
  my $credit = $ua->mp_post(
    "$ledger_path/credits",
    {
      type => 'Simulated',
      send_receipt => 1,
      attributes => {
        amount => $price,
      },
    },
  );
  $self->assert_n_deliveries(1, "receipt");
  $self->elapse(3);
  $self->assert_n_deliveries(1, "invoice");

  my $consumer_guid;

  Moonpig->env->storage->do_rw(sub {
    $ledger = Moonpig->env->storage
      ->retrieve_ledger_for_guid($v1->{ledger_guid});
    $consumer = $ledger->active_consumer_for_xid($a_xid);
    $consumer_guid = $consumer->guid;

    ok($consumer->replacement, "account has a replacement");
    ok($consumer->has_replacement, "account has a replacement (predicate)");
    isnt($consumer->replacement->guid, $consumer->guid,
         "replacement is different");
    ok($consumer->replacement->does("Moonpig::Role::Consumer::ByTime"),
         "replacement is another ByTime");
    ok(! $consumer->replacement->unapplied_amount, "replacement is unfunded");
    ok(! $consumer->replacement->is_expired, "replacement has not yet expired");
  });

  $ua->mp_post("$ledger_path/consumers/active/$a_xid/cancel", {});

  Moonpig->env->storage->do_rw(sub {
    $ledger = Moonpig->env->storage
      ->retrieve_ledger_for_guid($v1->{ledger_guid});
    $consumer = $ledger->consumer_collection
      ->find_by_guid({ guid => $consumer_guid });

    is($consumer->replacement, undef, "no replacement, anymore");

    is_deeply(
      [ $consumer->replacement_plan_parts ],
      [ get => '/nothing' ],
      "no replacement planned, either",
    );
  });
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
    "$ledger_path/credits",
    {
      type => 'Simulated',
      send_receipt => 1,
      attributes => {
        amount => $price,
      },
    });
  $self->assert_n_deliveries(1, "receipt");
  $self->elapse(1);

  Moonpig->env->storage->do_rw(sub {
    $ledger = Moonpig->env->storage
      ->retrieve_ledger_for_guid($v1->{ledger_guid});
    $consumer = $ledger->consumer_collection->find_by_xid({ xid => $a_xid });
    ok(! $consumer->replacement, "account has no replacement yet");

    my @plan = $consumer->replacement_plan_parts;
    isnt($plan[1], "/nothing", "replacement plan uri is not 'nothing'");
  });

  $ua->mp_post("$ledger_path/consumers/xid/$a_xid/cancel", {});

  Moonpig->env->storage->do_rw(sub {
    $ledger = Moonpig->env->storage
      ->retrieve_ledger_for_guid($v1->{ledger_guid});
    $consumer = $ledger->consumer_collection->find_by_xid({ xid => $a_xid });

    my @plan = $consumer->replacement_plan_parts;
    is($plan[1], "/nothing", "replacement plan uri is now 'nothing'");
  });
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

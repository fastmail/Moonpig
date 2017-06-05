
use JSON;
use Moonpig::App::Ob::Dumper qw();
use t::lib::TestEnv;
use Moonpig::UserAgent;
use Moonpig::Util qw(days dollars);
use Moonpig::Web::App;
use Plack::Test;
use Test::Deep qw(cmp_deeply re bool superhashof ignore);
use Test::More;
use Test::Routine;
use Test::Routine::Util '-all';

use lib 'eg/fauxbox/lib';
use Fauxbox::Moonpig::TemplateSet;

with ('Moonpig::Test::Role::LedgerTester');

around run_test => sub {
  my ($orig) = shift;
  my ($self) = shift;
  local $ENV{FAUXBOX_STORAGE_ROOT} =
    local $ENV{MOONPIG_STORAGE_ROOT} = $self->tempdir;
#  warn "# Using tempdir $ENV{FAUXBOX_STORAGE_ROOT}\n";
#  print STDERR "Pausing... ";
#  my $x = <STDIN>;
  return $self->$orig(@_);
};

my $ua = Moonpig::UserAgent->new({ base_uri => "http://localhost:5001" });
my $json = JSON->new;
my $app = Moonpig::Web::App->app;

my $guid_re = re('^[A-F0-9]{8}(-[A-F0-9]{4}){3}-[A-F0-9]{12}$');
my $date_re = re('^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d$');

my $price = dollars(20);

my $i = 0;
sub setup_account {
  my ($self) = @_;
  my %rv;

  $i++;
  my $x_username = 'testuser-' . $i;
  my $u_xid = username_xid($x_username);
  my $a_xid = "test:account:$i";
  my $ledger_path = "/ledger/by-xid/$u_xid";

  my $signup_info = {
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
            guid        => $guid_re
          }),
        );
        $result->{guid};
      };

      $rv{account_guid} = do {
        my $account_info = {
          template      => 'fauxboxtest',
          template_args => {
            xid         => $a_xid,
            make_active => 1,
            charge_amount => $price,
            replacement_lead_time     => days(2),
            charge_frequency => days(1),
            grace_period_duration => days(7),

            # 5 is just too short when we need to dun twice
            cost_period => days(10),
          },
        };

        my $result = $ua->mp_post("$ledger_path/consumers",
                                  $account_info);
        cmp_deeply($result, superhashof({ guid => $guid_re }));

        $result;
      };

      $self->elapse(1, $rv{ledger_guid});
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
            charges   => ignore(),
          }),
        ],
        "there is one payable invoice -- what we expect",
      );

      my $invoice_guid = $invoices->[0]{guid};
      my $invoice = $ua->mp_get("$ledger_path/invoices/guid/$invoice_guid");
      cmp_deeply(
        $invoice,
        superhashof({
          created_at   => $date_re,
          guid         => $invoice_guid,
          closed_at    => bool(1),
          paid_at      => bool(0),
          total_amount => $price,
          charges      => ignore(),
        }),
      );
    };

  return \%rv;
}

test "single payment" => sub {
  my ($self) = @_;

  my $rv = $self->setup_account;

  my $credit = $ua->mp_post(
    "/ledger/by-guid/$rv->{ledger_guid}/credits",
    {
      type => 'Simulated',
      attributes => {
        amount => $price,
      },
    });

  cmp_deeply(
    $credit,
    superhashof({
      amount           => $price,
      created_at       => $date_re,
      guid             => $guid_re,
      type             => "Simulated",
      unapplied_amount => dollars(0),
    }),
  );
};

test "setup autocharger" => sub {
  my ($self) = @_;

  my $rv = $self->setup_account;

  {
    my $ledger = $ua->mp_get("/ledger/by-guid/$rv->{ledger_guid}");
    is($ledger->{amount_due}, dollars(20), "we start off owing 20 bucks");
  }

  {
    my $autocharger = $ua->mp_get("/ledger/by-guid/$rv->{ledger_guid}/autocharger");
    is($autocharger, undef, "no autocharger yet");
  }

  {
    my $autocharger = $ua->mp_post(
      "/ledger/by-guid/$rv->{ledger_guid}/setup-autocharger",
      {
        template => 'moonpay',
        template_args => {
          amount_available => dollars(21),
        },
      },
    );

    is($autocharger->{amount_available}, dollars(21), "21 bucks in charger");
  }

  {
    my $autocharger = $ua->mp_get("/ledger/by-guid/$rv->{ledger_guid}/autocharger");
    cmp_deeply(
      $autocharger,
      superhashof({ ledger_guid => $rv->{ledger_guid} }),
      "...autocharger created via POST",
    );

    is($autocharger->{amount_available}, dollars(21), "21 bucks in charger");
  }

  # Gotta get to next dunning, 3d later. -- rjbs, 2016-01-26
  $self->elapse(4, $rv->{ledger_guid});

  {
    my $ledger = $ua->mp_get("/ledger/by-guid/$rv->{ledger_guid}");
    is($ledger->{amount_due}, 0, "once we have an autocharger, we autopay");
  }

  {
    my $autocharger = $ua->mp_get("/ledger/by-guid/$rv->{ledger_guid}/autocharger");
    my $ledger = $ua->mp_get("/ledger/by-guid/$rv->{ledger_guid}");
    is($autocharger->{amount_available}, dollars(1), "1 buck in charger");
  }

  $self->assert_n_deliveries(1, "invoice for replacement service");

  {
    my $ledger = $ua->mp_get("/ledger/by-guid/$rv->{ledger_guid}");
    is($ledger->{amount_due}, 0, "once we have an autocharger, we autopay");
  }
};

test "use autocharge by hand" => sub {
  my ($self) = @_;

  my $rv = $self->setup_account;

  {
    my $ledger = $ua->mp_get("/ledger/by-guid/$rv->{ledger_guid}");
    is($ledger->{amount_due}, dollars(20), "we start off owing 20 bucks");
  }

  {
    my $autocharger = $ua->mp_get("/ledger/by-guid/$rv->{ledger_guid}/autocharger");
    is($autocharger, undef, "no autocharger yet");
  }

  my $autocharger = $ua->mp_post(
    "/ledger/by-guid/$rv->{ledger_guid}/setup-autocharger",
    {
      template => 'moonpay',
      template_args => {
        amount_available => dollars(21),
      },
    },
  );

  {
    my $autocharger = $ua->mp_get("/ledger/by-guid/$rv->{ledger_guid}/autocharger");
    cmp_deeply(
      $autocharger,
      superhashof({ ledger_guid => $rv->{ledger_guid} }),
      "...autocharger created via POST",
    );
    is($autocharger->{amount_available}, dollars(21), "21 bucks in charger");
  }

  {
    my $credit_pack = $ua->mp_post(
      "/ledger/by-guid/$rv->{ledger_guid}/autocharge-amount-due",
      {},
    );
    is($credit_pack->{amount}, dollars(20));
  }

  {
    my $ledger = $ua->mp_get("/ledger/by-guid/$rv->{ledger_guid}");
    is($ledger->{amount_due}, 0, "we can trigger autopay by hand");
  }

  {
    my $autocharger = $ua->mp_get("/ledger/by-guid/$rv->{ledger_guid}/autocharger");
    is($autocharger->{amount_available}, dollars(1), "1 buck in charger");
  }
};

test "clear autocharger" => sub {
  my ($self) = @_;

  my $rv = $self->setup_account;

  {
    my $ledger = $ua->mp_get("/ledger/by-guid/$rv->{ledger_guid}");
    is($ledger->{amount_due}, dollars(20), "we start off owing 20 bucks");
  }

  {
    my $autocharger = $ua->mp_get("/ledger/by-guid/$rv->{ledger_guid}/autocharger");
    is($autocharger, undef, "no autocharger yet");
  }

  my $autocharger = $ua->mp_post(
    "/ledger/by-guid/$rv->{ledger_guid}/setup-autocharger",
    {
      template => 'moonpay',
      template_args => {
        amount_available => dollars(21),
      },
    },
  );

  {
    my $autocharger = $ua->mp_get("/ledger/by-guid/$rv->{ledger_guid}/autocharger");
    cmp_deeply(
      $autocharger,
      superhashof({ ledger_guid => $rv->{ledger_guid} }),
      "...autocharger created via POST",
    );
    is($autocharger->{amount_available}, dollars(21), "21 bucks in charger");
  }

  {
    $ua->mp_post(
      "/ledger/by-guid/$rv->{ledger_guid}/clear-autocharger",
      {},
    );

    my $autocharger = $ua->mp_get("/ledger/by-guid/$rv->{ledger_guid}/autocharger");
    is($autocharger, undef, "autocharger destroyed by clear-autocharger");
  }
};

sub elapse {
  my ($self, $days, $ledger_guid) = @_;
  $days ||= 1;
  for (1 .. $days) {
    $ua->mp_get("/advance-clock/86400");
    $ua->mp_post("/ledger/by-guid/$ledger_guid/heartbeat", {});
  }
}

sub Dump {
  my ($what) = @_;
  my $text = Moonpig::App::Ob::Dumper::Dump($what);
  $text =~ s/^/# /gm;
  warn $text;
}

sub username_xid { "test:username:$_[0]" }

run_me;
done_testing;

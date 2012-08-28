use Test::Routine;
use Test::Routine::Util -all;
use Test::More;

use HTTP::Request;
use Moonpig::Web::App;
use Plack::Test;

use t::lib::TestEnv;

use Moonpig::Util qw(days weeks years);
use Moonpig::Test::Factory qw(do_with_fresh_ledger);
use Moonpig::UserAgent;
use t::lib::ConsumerTemplateSet::Demo;

with(
  'Moonpig::Test::Role::LedgerTester',
);

use namespace::autoclean;

my $jan1 = Moonpig::DateTime->new(year => 2000, month => 1, day => 1);

test "import a ledger via the web" => sub {
  my ($self) = @_;

  my $xid = 'test:xyz';

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
      $xid => {
        template      => 'demo-service',
        template_args => {
          make_active => 1,
          minimum_chain_duration => years(6),
        },
      },
    },

    old_payment_info   => { sample => [ { payment => 'money!' } ] },
  };

  my $ua = Moonpig::UserAgent->new({ base_uri => "http://localhost:5001" });

  my $guid;

  Moonpig->env->stop_clock_at( $jan1 );

  my $replacement_date_str;
  test_psgi(Moonpig::Web::App->app, sub {
    my ($cb) = @_;

    $ua->set_test_callback($cb);

    my $result = $ua->mp_post('/ledgers', $signup_info);

    $guid = $result->{guid};
    ok($guid, "created ledger via post ($guid)");

    my $consumer_guid = $result->{active_xids}{$xid}{guid};
    my $url = sprintf '/ledger/by-guid/%s/consumers/guid/%s/%s?include_unpaid_charges=0',
      $guid,
      $consumer_guid,
      'replacement_chain_expiration_date';
    $replacement_date_str = $ua->mp_get($url);

    my $guids = $ua->mp_get('/ledgers');
    is_deeply($guids, [ $guid ], "we can GET /ledgers for guids");
  });

  my $consumer_guid;
  my $expected_expiration_date = $jan1 + weeks(6*52);
  Moonpig->env->storage->do_ro_with_ledger(
    $guid,
    sub {
      my ($ledger) = @_;
      my @credits = $ledger->credits;
      is(@credits, 1, "we made one credit by importing");
      ok($credits[0]->is_refundable, "...and it is refundable");

      my @consumers = $ledger->active_consumers;
      is(@consumers, 1, "we have one active consumer");
      {
        my $c = $consumers[0];
        $consumer_guid = $c->guid;
      }

      # This is 6*52 weeks, not 6 years, because these consumers charge weekly,
      # and so they run out of money after 52 such charges; the extra 1.25 days
      # worth of money are absorbed. -- mjd, 2012-06-04
      # XXX 20120605 mjd Actually it should be 6*53 weeks, because
      # each consumer fails over to the next only at the *end* of its
      # last incompletely funded charge period; fix this when we add
      # the round_up option to ignore_partial_charge_periods as per 20120605
      # comments elsewhere.
      my $exp_date = $consumers[0]->replacement_chain_expiration_date(
        { include_unpaid_charges => 0 });

      cmp_ok(
        abs($exp_date - $expected_expiration_date), '<', 86_400,
        "our chain's estimated exp. date is within a day of expectations",
      );

      is($replacement_date_str, "$exp_date" =~ s/T/ /r, "...same as via HTTP");
    },
  );

  Moonpig->env->storage->do_ro_with_ledger(
    $guid,
    sub {
      my ($ledger) = @_;
      $self->heartbeat_and_send_mail($ledger);
      my @deliveries = Moonpig->env->email_sender->deliveries;
      is(@deliveries, 0, "we didn't email any invoices, they're internal");
    },
  );

#  Moonpig->env->stop_clock_at( $expected_expiration_date - days(5) );
  note "waiting for entire chain to expire...";
  Moonpig->env->storage->do_rw_with_ledger(
    $guid,
    sub {
      my ($ledger) = @_;
      my $exp_date = ($ledger->active_consumers)[0]
        ->replacement_chain_expiration_date({ include_unpaid_charges => 0 });
      my $last = $ledger->consumer_collection->find_by_guid({ guid => $consumer_guid });
      $last = $last->replacement while $last->has_replacement;

      my $last_unexpired_date;
      until ($last->is_expired) {
        $last_unexpired_date = Moonpig->env->now;
        $ledger->heartbeat;
        Moonpig->env->elapse_time(86_400);
      }
      is ($last_unexpired_date->iso, $exp_date->iso, "predicted chain expiration date was correct");
    });

};

test "import a ledger, with proration, via the web" => sub {
  my ($self) = @_;

  my $xid = 'test:xyz';

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
      $xid => {
        template      => 'demo-service',
        template_args => {
          make_active => 1,
          proration_period => 43_200, # 12 hours
        },
      },
    },

    old_payment_info   => { sample => [ { payment => 'money!' } ] },
  };

  my $ua = Moonpig::UserAgent->new({ base_uri => "http://localhost:5001" });

  my $guid;

  Moonpig->env->stop_clock_at(
    Moonpig::DateTime->new(year => 2000, month => 1, day => 1),
  );

  my $replacement_date_str;
  test_psgi(Moonpig::Web::App->app, sub {
    my ($cb) = @_;

    $ua->set_test_callback($cb);

    my $result = $ua->mp_post('/ledgers', $signup_info);

    $guid = $result->{guid};
    ok($guid, "created ledger via post ($guid)");

    my $consumer_guid = $result->{active_xids}{$xid}{guid};
    my $url = sprintf '/ledger/by-guid/%s/consumers/guid/%s/%s',
      $guid,
      $consumer_guid,
      'replacement_chain_expiration_date';
    $replacement_date_str = $ua->mp_get($url);

    my $guids = $ua->mp_get('/ledgers');
    is_deeply($guids, [ $guid ], "we can GET /ledgers for guids");
  });

  Moonpig->env->storage->do_ro_with_ledger(
    $guid,
    sub {
      my ($ledger) = @_;
      my @credits = $ledger->credits;
      is(@credits, 1, "we made one credit by importing");
      ok($credits[0]->is_refundable, "...and it is refundable");

      my @consumers = $ledger->active_consumers;
      is(@consumers, 1, "we have one active consumer");

      my $expected = Moonpig->env->now + days(.5);
      my $exp_date = $consumers[0]->replacement_chain_expiration_date;

      cmp_ok(
        abs($exp_date - $expected), '<', 86_400,
        "our chain's estimated exp. date is within a day of expectations",
      );

      is($replacement_date_str, "$exp_date" =~ s/T/ /r, "...same as via HTTP");
    },
  );

  Moonpig->env->storage->do_rw_with_ledger(
    $guid,
    sub {
      my ($ledger) = @_;

      $self->heartbeat_and_send_mail($ledger);
      my @deliveries = Moonpig->env->email_sender->deliveries;
      is(@deliveries, 0, "we didn't email any invoices, they're internal");

      my $c_guid = $ledger->active_consumer_for_xid($xid)->guid;

      Moonpig->env->elapse_time(86_400 * 4); # 3d grace + 1d
      $ledger->heartbeat;
      my $repl_guid = $ledger->active_consumer_for_xid($xid)->guid;
      isnt($repl_guid, $c_guid, 'after grace period, we get a replacement');
    },
  );
};

test "import a b5g1 ledger via the web, avoiding b5g1" => sub {
  my ($self) = @_;

  my $xid = 'test:xyz';

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
      $xid => {
        template      => 'b5g1_paid',
        template_args => {
          make_active => 1,
          minimum_chain_duration => days(60),
        },
      },
    },

    old_payment_info   => { sample => [ { payment => 'money!' } ] },
  };

  my $ua = Moonpig::UserAgent->new({ base_uri => "http://localhost:5001" });

  my $guid;

  Moonpig->env->stop_clock_at( $jan1 );

  my $replacement_date_str;
  test_psgi(Moonpig::Web::App->app, sub {
    my ($cb) = @_;

    $ua->set_test_callback($cb);

    my $result = $ua->mp_post('/ledgers', $signup_info);

    $guid = $result->{guid};
    ok($guid, "created ledger via post ($guid)");
  });

  Moonpig->env->storage->do_ro_with_ledger(
    $guid,
    sub {
      my ($ledger) = @_;

      my ($head, $wtf) = $ledger->active_consumers;
      ok(! $wtf, "we have one active consumer");

      my @chain = ($head, $head->replacement_chain);
      my @free  = grep {; $_->does('Moonpig::Role::Consumer::SelfFunding') }
                  @chain;

      is(@free, 0, "there's no self-funding consumer");
    },
  );
};

run_me;
done_testing;

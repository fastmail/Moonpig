use Test::Routine;
use Test::Routine::Util -all;
use Test::More;

use HTTP::Request;
use Moonpig::Web::App;
use Plack::Test;

use t::lib::TestEnv;

use Moonpig::Util qw(days years);
use Moonpig::Test::Factory qw(do_with_fresh_ledger);
use Moonpig::UserAgent;
use t::lib::ConsumerTemplateSet::Demo;

with(
  'Moonpig::Test::Role::UsesStorage',
);

use namespace::autoclean;

test "get a ledger guid via web" => sub {
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

    invoice_internally => 1,
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

      # the "- days(1)" is because the heartbeat implicit to creation charges
      # for the first day! -- rjbs, 2012-03-01
      my $expected = Moonpig->env->now + years(6) - days(1);
      my $exp_date = $consumers[0]->replacement_chain_expiration_date;

      cmp_ok(
        abs($exp_date - $expected), '<', 86_400,
        "our chain's estimated exp. date is within a day of expectations",
      );

      is($replacement_date_str, "$exp_date" =~ s/T/ /r, "...same as via HTTP");
    },
  );
};

run_me;
done_testing;

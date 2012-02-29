use Test::Routine;
use Test::Routine::Util -all;
use Test::More;

use HTTP::Request;
use Moonpig::Web::App;
use Plack::Test;

use t::lib::TestEnv;

use Moonpig::Util qw(years);
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
          replacement_chain_duration => years(5),
        },
      },
    },

    old_payment_info => { sample => [ { payment => 'money!' } ] },
  };

  my $ua = Moonpig::UserAgent->new({ base_uri => "http://localhost:5001" });

  my $guid;

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
      my @credits = $ledger->credits;
      is(@credits, 2, "we made two credits by importing");
      my ($r_credit) = grep { $_->does('Moonpig::Role::Credit::Refundable') } @credits;
      my ($n_credit) = grep {!$_->does('Moonpig::Role::Credit::Refundable') } @credits;

      ok($r_credit, "one is refundable");
      ok($n_credit, "one is not refundable");
      cmp_ok($r_credit->amount, '>', $n_credit->amount, "mostly it's refundable");
    },
  );
};

run_me;
done_testing;

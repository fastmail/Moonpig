
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

with ('Moonpig::Test::Role::UsesStorage');

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
    { name => "Fred Flooney",
      email_addresses => [ 'textuser@example.com' ],
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
        );
        $result->{guid};
      };

      $rv{account_guid} = do {
        my $account_info = {
          template      => 'fauxboxtest',
          template_args => {
            xid         => $a_xid,
            make_active => 1,
            cost_amount => $price,
            old_age     => days(2),
            charge_frequency => days(1),
          },
        };

        my $result = $ua->mp_post("$ledger_path/consumers",
                                  $account_info);
        cmp_deeply($result, superhashof({ guid => $guid_re }));

        $result;
      };

      $self->elapse(1);

      my $invoices = $ua->mp_get("$ledger_path/invoices/unpaid");

      cmp_deeply(
        $invoices,
        [
          superhashof({
            date => $date_re,
            guid => $guid_re,
            is_paid   => bool(0),
            is_closed => bool(1),
            total_amount => $price,
            charges   => ignore(),
          }),
        ],
        "there is one unpaid invoice -- what we expect",
      );

      my $invoice_guid = $invoices->[0]{guid};
      my $invoice = $ua->mp_get("$ledger_path/invoices/guid/$invoice_guid");
      cmp_deeply(
        $invoice,
        superhashof({
          date         => $date_re,
          guid         => $invoice_guid,
          is_closed    => bool(1),
          is_paid      => bool(0),
          total_amount => $price,
          charges      => ignore(),
        }),
      );
    };

  return \%rv;
}


test "single payment" => sub {
  my ($self) = @_;

  my $v1 = $self->setup_account;

  my $credit = $ua->mp_post(
    "$ledger_path/credits",
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
      type             => "Credit::Simulated",
      unapplied_amount => dollars(0),
    }),
  );
};

sub elapse {
  my ($self, $days) = @_;
  $days ||= 1;
  for (1 .. $days) {
    $ua->mp_get("/advance_clock/86400");
    $ua->mp_post("$ledger_path/heartbeat", {});
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

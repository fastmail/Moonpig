
use JSON;
use Moonpig::App::Ob::Dumper qw();
use Moonpig::Env::Test;
use Moonpig::UserAgent;
use Moonpig::Util qw(dollars);
use Moonpig::Web::App;
use Plack::Test;
use Test::Deep;
use Test::More;
use Test::Routine;
use Test::Routine::Util '-all';

use lib 'eg/fauxbox/lib';
use Fauxbox::Moonpig::TemplateSet;

use strict;

with ('t::lib::Role::UsesStorage');

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
my $ledger_path = "/ledger/xid/$u_xid";

my $guid_re = re('^[A-F0-9]{8}(-[A-F0-9]{4}){3}-[A-F0-9]{12}$');
my $date_re = re('^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d$');

test "sign up" => sub {
  my ($self) = @_;

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

      my $ledger_guid = do {
        my $result = $ua->mp_post('/ledgers', $signup_info);
        cmp_deeply($result,
                   { value =>
                       { active_xids => { $u_xid => $guid_re },
                         guid => $guid_re
                        } } );
      };

      my $account_guid = do {
        my $account_info = {
          template      => 'fauxboxtrivial',
          template_args => {
            xid         => $a_xid,
            make_active => 1,
            cost_amount => dollars(20),
          },
        };

        my $result = $ua->mp_post("$ledger_path/consumers",
                                  $account_info);


        cmp_deeply($result,
                   { value => $guid_re });
        $result->{value};
      };

      {
        $self->elapse(1);
        my $last_rfp = $ua->mp_get("$ledger_path/rfps/last");
        cmp_deeply($last_rfp,
                   { value =>
                       { guid => $guid_re,
                         invoices => [ $guid_re ],
                         sent_at => $date_re,
                       } } );

        my $rfp_guid = $last_rfp->{value}{guid};
        my $invoice_guid = $last_rfp->{value}{invoices}[0];

        my $invoice_c = $ua->mp_get("$ledger_path/rfps/last/invoices");
        cmp_deeply($invoice_c,
                   { value =>
                       { items => [ $invoice_guid ],
                         owner => $rfp_guid,
                         what => "InvoiceCollection"
                        } } );

        my $invoice = $ua->mp_get("$ledger_path/invoices/guid/$invoice_guid");
        cmp_deeply($invoice,
                   { value =>
                       { date => $date_re,
                         guid => $invoice_guid,
                         is_closed => $JSON::XS::true,
                         is_paid => $JSON::XS::false,
                         total_amount => dollars(20),
                       } } );
      }

      {
        my $credit = $ua->mp_post(
          "$ledger_path/credits/accept_payment",
          {
            amount => dollars(20),
            type => 'Simulated',
          });
        cmp_deeply($credit,
                   { value =>
                       { amount => dollars(20),
                         created_at => $date_re,
                         guid => $guid_re,
                         type => "Credit::Simulated",
                         unapplied_amount => dollars(0),
                       } } );
      }
    };
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

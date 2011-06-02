

use JSON;
use Moonpig::Env::Test;
use Moonpig::UserAgent;
use Moonpig::Web::App;
use Plack::Test;
use Test::More;
use Test::Routine;
use Test::Routine::Util '-all';

with ('t::lib::Role::UsesStorage');
around run_test => sub {
  my ($orig) = shift;
  my ($self) = shift;
  local $ENV{MOONPIG_STORAGE_ROOT} = $self->tempdir;
  return $self->$orig(@_);
};

my $ua = Moonpig::UserAgent->new({ base_uri => "http://localhost:5001" });
my $json = JSON->new;

test "raw HTTP response" => sub {
  # Test raw responses from Moonpig app
  # (Make sure the HTTP responses have the right headers, etc.)

  test_psgi
    app => Moonpig::Web::App->app,
    client => sub {
      my $cb = shift;
      $ua->set_test_callback($cb);
      my $resp = $ua->get($ua->qualify_path('/time'));
      is($resp->content_type, "application/json", "content-type");
      ok(my $result = $json->decode($resp->content), "response contains JSON");
      is(keys(%$result), 1, "one key");
      my $time = $result->{now};
      ok(defined $time, "response contains time");
      ok(time() - $time < 5, "response is current time");
    };
};

test "basic response" => sub {
  test_psgi
    app => Moonpig::Web::App->app,
    client => sub {
      my $cb = shift;
      $ua->set_test_callback($cb);
      my $result = $ua->mp_get('/time');
      is(keys(%$result), 1, "one key");
      my $time = $result->{now};
      ok(defined $time, "response contains time");
      ok(time() - $time < 5, "response is current time");
    };
};

run_me;
done_testing;

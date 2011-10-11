use Test::Routine;
use Test::Routine::Util -all;
use Test::More;

use HTTP::Request;
use Moonpig::Web::App;
use Plack::Test;

use Moonpig::Test::Factory qw(build_ledger);

with(
  't::lib::Role::UsesStorage',
);

use Moonpig::Context::Test -all, '$Context';

use namespace::autoclean;

test "get a ledger guid via web" => sub {
  my ($self) = @_;

  my $ledger = build_ledger();

  my $guid = $ledger->guid;

  Moonpig->env->save_ledger($ledger);

  test_psgi(Moonpig::Web::App->app, sub {
    my ($cb) = @_;

    my $req = HTTP::Request->new(
      GET => "http://localhost/ledger/by-guid/$guid/gguid",
    );

    my $res = $cb->($req);

    ok($res->is_success, "we got a successful response from the web app");
    is($res->content_type, 'application/json', "response is JSON");

    my $payload = JSON->new->decode($res->content)->{value};
    is_deeply($payload, $guid, "the payload is the expected GUID");
  });
};

run_me;
done_testing;

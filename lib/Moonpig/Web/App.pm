use strict;
use warnings;
package Moonpig::Web::App;

use JSON;
use Moonpig;
use Try::Tiny;

use Plack::Request;

sub app {
  return sub {
    my ($env) = @_;

    my $JSON = JSON->new;

    my $req = Plack::Request->new($env);
    my @path = split q{/}, $req->path_info;
    shift @path; # get rid of leading "/" part

    my $response = try {
      my $resource = Moonpig->env->route(\@path);
      my $result   = $resource->resource_request(lc $req->method, {});
      return [
        200,
        [ 'Content-type' => 'application/json' ],
        [ $JSON->encode({ result => $result }) ],
      ];
    } catch {
      if (try { $_->isa('Moonpig::X::Route') }) {
        return [
          404,
          [ 'Content-type' => 'application/json' ],
          [ $JSON->encode({ error => "no such resource" }) ],
        ];
      } else {
        return [
          500,
          [ 'Content-type' => 'application/json' ],
          [ $JSON->encode({ error => "unknown" }) ],
        ];
      }
    };

    return $response;
  }
}

1;

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
      return $_->as_psgi if try { $_->does('HTTP::Throwable') };
      return HTTP::Throwable::Factory->new_exception(InternalServerError => {
        show_stack_trace => 0,
      })->as_psgi;
    };

    return $response;
  }
}

1;

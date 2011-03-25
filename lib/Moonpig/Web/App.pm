use strict;
use warnings;
package Moonpig::Web::App;

use JSON;
use Moonpig;
use Stick::Util qw(ppack);
use Try::Tiny;

use Plack::Request;

my $JSON = JSON->new->ascii(1)->convert_blessed(1)->allow_blessed(1);

sub app {
  return sub {
    my ($env) = @_;

    my $req = Plack::Request->new($env);
    my @path = split q{/}, $req->path_info;
    shift @path; # get rid of leading "/" part

    my $response = try {
      my $resource = Moonpig->env->route(\@path);

      my $args = {};
      if ($req->content_type eq 'application/json') {
        $args = $JSON->decode($req->content);
      }

      my $result = $resource->resource_request(lc $req->method, $args);
      return [
        200,
        [ 'Content-type' => 'application/json' ],
        [ $JSON->encode( ppack($result) ) ],
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

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
      my $result = Moonpig->env->route(lc $req->method, \@path, {});
      return [
        200,
        [ 'Content-type' => 'JSON' ],
        [ $JSON->encode({ result => $result }) ],
      ];
    } catch {
      die $_;
    };

    return $response;
  }
}

1;

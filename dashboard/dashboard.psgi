#!perl
use strict;
use warnings;

use lib 'lib';

use File::Spec;
use HTML::Mason::Interp;
use Path::Class;
use Plack::Request;
use Router::Dumb;
use Router::Dumb::Helper::FileMapper;
use Router::Dumb::Helper::RouteFile;

use namespace::autoclean;

{
  package HTML::Mason::Commands;
  use Data::Dumper::HTML qw(dumper_html);

  sub mc { sprintf '$%.02f', ((shift) / 100_000) }
}

my $router = Router::Dumb->new;

Router::Dumb::Helper::FileMapper->new({
  root          => 'dashboard/mason/public',
  target_munger => sub {
    my ($self, $filename) = @_;
    dir('public')->file( file($filename)->relative($self->root) )->stringify;
  },
})->add_routes_to($router);

Router::Dumb::Helper::RouteFile->new({ filename => 'dashboard/routes' })
                               ->add_routes_to($router);

my $interp = HTML::Mason::Interp->new(
  comp_root     => File::Spec->rel2abs("dashboard/mason"),
  request_class => 'Moonpig::Dashboard::Request',
);

return sub {
  my ($env) = @_;
  my $req = Plack::Request->new($env);

  my $match = $router->route( $req->path_info );

  return [ 404 => [ ], [ ] ] unless $match;

  warn $match->target;
  my $comp = $interp->load( '/' . $match->target );

  my $output = '';
  $interp->make_request(
    comp => $comp,
    args => [ $match->matches ],
    out_method => \$output,
  )->exec;

  return [
    200 => [ 'Content-Type' => 'text/html' ], [ $output ]
  ];
}

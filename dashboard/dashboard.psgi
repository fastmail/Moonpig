#!perl
use strict;
use warnings;

use lib 'lib';

use File::Spec;
use HTML::Mason::PSGIHandler;
use Plack::Builder;
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
    dir('mason/public')->file( file($filename)
                       ->relative($self->root) )
                       ->stringify;
  },
})->add_routes_to($router);

Router::Dumb::Helper::RouteFile->new({ filename => 'dashboard/routes' })
                               ->add_routes_to($router);

my $interp = HTML::Mason::Interp->new(
  comp_root     => File::Spec->rel2abs("dashboard/mason"),
  # request_class => 'Moonpig::Dashboard::Request',
);

my $comp = $interp->load("/index");

my $output = '';
$interp->make_request(
  comp => $comp,
  args => [ ],
  out_method => \$output,
)->exec;

print $output;
# my $handler = sub {
#   my $env = shift;
#   my $res = $h->handle_psgi($env);
#   return $res;
# };

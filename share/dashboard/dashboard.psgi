#!perl
use strict;
use warnings;

use if $ENV{MOONPIG_DASHBOARD_TEST}, lib => 'lib';
use if $ENV{MOONPIG_DASHBOARD_TEST}, 'Test::File::ShareDir',
  -share => { -dist => { q{Moonpig} => q{share} } };

use Encode qw(encode_utf8);
use File::ShareDir qw(dist_dir);
use File::Spec;
use HTML::Mason::Interp;
use HTML::MasonX::Free::Compiler;
use HTML::MasonX::Free::Component;
use HTML::MasonX::Free::Resolver;
use Path::Class;
use Plack::App::Proxy;
use Plack::Builder;
use Plack::Request;
use Router::Dumb;
use Router::Dumb::Helper::FileMapper;
use Router::Dumb::Helper::RouteFile;
use Try::Tiny;

use Moonpig::Logger '$Logger' => { init => {
  ident    => 'moonpig-dashboard',
  facility => 'local6',
} };

use namespace::autoclean;

package HTML::Mason::Commands {
  use Data::GUID qw(guid_string);
  use Moonpig::App::Ob::Dumper ();
  use List::Util ();

  sub mc {
    my ($mc) = @_;
    my $dol = $mc / (100 * 1000);
    my $fmt = sprintf '%.6f', $dol;

    my $fcent = substr $fmt, -4, 4, '';

    my $str = sprintf '$%.02f', $fmt;
    $str .= '+' unless $fcent eq '0000';

    return $str;
  }

  sub sum {
    return List::Util::reduce(sub { $a + $b }, 0, @_);
  }

  sub sumof (&@) {
    my ($f, @list) = @_;
    sum(map $f->($_), @list);
  }
}

my $router = Router::Dumb->new;

my $core_root = dir( dist_dir('Moonpig') )->subdir(qw(dashboard));

for my $root (
  map {; dir($_)->subdir(qw(dashboard)) } Moonpig->env->share_roots
) {
  # GET targets
  Router::Dumb::Helper::FileMapper->new({
    root          => $root->subdir(qw(mason public))->stringify,
    target_munger => sub {
      my ($self, $filename) = @_;
      dir('public')->file( file($filename)->relative($self->root) )->stringify;
    },
  })->add_routes_to($router, { ignore_conflicts => 1 });

  # POST targets
  Router::Dumb::Helper::FileMapper->new({
    root          => $root->subdir(qw(mason post))->stringify,
    parts_munger  => sub { unshift @{ $_[1] }, 'post'; $_[1] },
    target_munger => sub {
      my ($self, $filename) = @_;
      dir('post')->file( file($filename)->relative($self->root) )->stringify;
    },
  })->add_routes_to($router, { ignore_conflicts => 1 });

  # Intentionally does not ignore conflicts -- rjbs, 2012-09-21
  if (-e (my $file = $root->file('routes')->stringify)) {
    Router::Dumb::Helper::RouteFile
      ->new({ filename => $file })
      ->add_routes_to($router);
  }
}

warn "ROUTING TABLE: \n";
for my $route ($router->ordered_routes) {
  warn sprintf "/%-50s -> %s\n", $route->path, $route->target;
}

my $root_depth = 0; # SORRY -- rjbs, 2012-09-20
my $interp = HTML::Mason::Interp->new(
  comp_root     => '/-',
  request_class => 'Moonpig::Dashboard::Request',
  compiler      => HTML::MasonX::Free::Compiler->new(
    allow_globals       => [ '$r' ],
    allow_stray_content => 0,
    default_method_to_call => 'main',
  ),
  resolver      => HTML::MasonX::Free::Resolver->new({
    comp_class     => 'HTML::MasonX::Free::Component',
    add_next_call  => 0,
    resolver_roots => [
      map {; [ $root_depth++ => dir($_)->subdir(qw(dashboard mason)) ] }
      Moonpig->env->share_roots,
    ],
  }),
);

my $app = sub {
  my ($env) = @_;
  my $req = Plack::Request->new($env);

  my $match = $router->route( $req->path_info );

  return [ 404 => [ 'Content-Type' => 'text/plain' ], [ 'not found' ] ]
    unless $match;

  my $comp = $interp->load( '/' . $match->target );

  try {
    my $output = '';

    $interp->set_global('$r', $req);

    $interp->make_request(
      comp => $comp,
      args => [
        %{ $req->body_parameters },
        $match->matches,
      ],
      out_method => \$output,
    )->exec;

    my $octets = encode_utf8($output);

    return [
      200 => [ 'Content-Type' => 'text/html; charset="utf-8"' ], [ $octets ]
    ];
  } catch {
    if (try { $_->isa('Moonpig::Dashboard::Redirect') }) {
      my $uri  = URI->new_abs( $_->uri, $req->uri );
      return [ 302, [ Location => $uri ], [] ];
    }
    die $_;
  };
};

builder {
  # enable 'Debug';

  # It isn't trivial to have this scan all the roots without thinking about it,
  # so I'm going to not think about it right now.  -- rjbs, 2012-09-21
  enable(
    "Plack::Middleware::Static",
    path => qr{^/(images|js|css)/},
    root => $core_root->subdir(qw(static)),
  );

  enable(
    "Plack::Middleware::AccessLog",
    logger => sub { $Logger->log($_[0]) },
  );

  mount "/moonpig" => Plack::App::Proxy->new(
    remote => $ENV{MOONPIG_URI},
  )->to_app;

  mount "/" => $app;
};

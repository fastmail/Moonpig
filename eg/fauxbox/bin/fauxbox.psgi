#!perl
use strict;
use warnings;

use lib 'eg/fauxbox/lib';

my $root = $ENV{FAUXBOX_STORAGE_ROOT} = 'eg/fauxbox/db';

use File::Spec;
use HTML::Mason::PSGIHandler;
use Plack::Util;

use Fauxbox::Mason::Request;
use Fauxbox::Schema;

use namespace::autoclean;

Fauxbox::Schema->shared_connection->deploy;

my $h = HTML::Mason::PSGIHandler->new(
  comp_root     => File::Spec->rel2abs("eg/fauxbox/mason"),
  request_class => 'Fauxbox::Mason::Request',
);

my $handler = sub {
  my $env = shift;
  my $res = $h->handle_psgi($env);

  if ($res->[0] > 399) {
    my $headers = Plack::Util::headers( $res->[1] );
    $headers->set('Content-Type' => 'text/plain');
    $headers->remove('Content-Length');

    $res->[2] = [ "Error code $res->[0]" ];
  }

  return $res;
};

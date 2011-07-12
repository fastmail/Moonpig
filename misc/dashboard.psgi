#!perl
use strict;
use warnings;

use lib 'lib';

use File::Spec;
use HTML::Mason::PSGIHandler;
use Plack::Builder;

{
  package HTML::Mason::Commands;
  use Data::Dumper::HTML qw(dumper_html);
}

use namespace::autoclean;

my $h = HTML::Mason::PSGIHandler->new(
  comp_root     => File::Spec->rel2abs("dashboard"),
  request_class => 'Moonpig::Dashboard::Request',
);

my $handler = sub {
  my $env = shift;
  my $res = $h->handle_psgi($env);
  return $res;
};

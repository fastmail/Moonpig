use strict;
use warnings;
package Moonpig::Web::App;

use JSON;
use Moonpig;
use Moonpig::Util qw(event);
use Stick::Util qw(ppack);
use Try::Tiny;

use Plack::Request;

my $JSON = JSON->new->ascii(1)->convert_blessed(1)->allow_blessed(1);

sub test_routes {
  my ($path, $storage) = @_;
  my @path = @$path;

  $storage->_reinstate_stored_time;

  if (@path == 1 and $path[0] eq 'heartbeat-all') {
    $storage->txn(sub {
      my @guids = $storage->known_guids;
      for my $guid (@guids) {
        my $ledger = $storage->retrieve_ledger_for_guid($guid);
        $ledger->handle_event( event('heartbeat') );
        $storage->store_ledger($ledger);
      }
    });

    return [
      200,
      [ 'Content-type' => 'application/json' ],
      [ $JSON->encode({ result => 'heartbeats processed' }) ],
    ];
  }

  if (@path == 1 and $path[0] eq 'time') {
    return [
      200,
      [ 'Content-type' => 'application/json' ],
      [ $JSON->encode({ now => Moonpig->env->now->epoch }) ],
    ];
  }

  if (@path == 2 and $path[0] eq 'advance-clock') {
    my $s = $path[1];
    Moonpig->env->stop_clock_at( Moonpig->env->now + $s );
    Moonpig->env->restart_clock;
    $storage->_store_time;
    $storage->_reinstate_stored_time;

    return [
      200,
      [ 'Content-type' => 'application/json' ],
      [ $JSON->encode({ now => Moonpig->env->now->epoch }) ],
    ];
  }
}

sub app {
  return sub {
    my ($env) = @_;

    my $storage = Moonpig->env->storage;

    my $req = Plack::Request->new($env);
    my @path = split q{/}, $req->path_info;
    shift @path; # get rid of leading "/" part

    my $response = try {

      # XXX: IF WE ARE IN TESTING MODE -- rjbs, 2011-03-30
      if (1) {
        my $res = test_routes(\@path, $storage);
        return $res if $res;
      }

      my $resource = Moonpig->env->route(\@path);

      my $args = {};
      if (($req->content_type || '') eq 'application/json') {
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

      my $r = HTTP::Throwable::Factory->new_exception(InternalServerError => {
        show_stack_trace => 0,
      })->as_psgi;

      # XXX: Colossal hack for now, for dev.
      {
        my $h = Plack::Util::headers($r->[1]);
        $h->remove('Content-Length');
        push @{ $r->[2] }, "\n\n", $_;
      }

      return $r;
    };

    return $response;
  }
}

1;

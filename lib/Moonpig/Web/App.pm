use strict;
use warnings;
package Moonpig::Web::App;
# ABSTRACT: Moonpig's PSGI web app package

use JSON;
use Moonpig;
use Stick::Util 0.20110525 qw(json_pack);
use Try::Tiny;

use Plack::Request;

my $JSON = JSON->new->ascii(1)->convert_blessed(1)->allow_blessed(1);

sub test_routes {
  my ($path, $storage) = @_;
  my @path = @$path;

  if (Moonpig->env->does('Moonpig::Role::Env::WithMockedTime')) {
    $storage->_reinstate_stored_time;
  }

  if (@path == 1 and $path[0] eq 'heartbeat-all') {
    $storage->do_with_ledgers([ $storage->ledger_guids ], sub {
      for my $ledger (@_) {
        $ledger->heartbeat;
      }
    });

    return [
      200,
      [ 'Content-type' => 'application/json' ],
      [ $JSON->encode({ value => { result => 'heartbeats processed' } }) ],
    ];
  }

  if (@path == 1 and $path[0] eq 'send-email') {
    my $count = Moonpig->env->process_email_queue;

    return [
      200,
      [ 'Content-type' => 'application/json' ],
      [
        $JSON->encode({ value => {
          result => 'email queue processed',
          sent   => $count,
        } })
      ],
    ];
  }

  if (@path == 1 and $path[0] eq 'time') {
    return [
      200,
      [ 'Content-type' => 'application/json' ],
      [ $JSON->encode({ value => { now => Moonpig->env->now->epoch } }) ],
    ];
  }

  if (@path == 2 and $path[0] eq 'advance-clock') {
    my $s = $path[1];
    Moonpig->env->stop_clock_at( Moonpig->env->now + $s );
    Moonpig->env->restart_clock;

    if (Moonpig->env->does('Moonpig::Role::Env::WithMockedTime')) {
      $storage->_store_time;
      $storage->_reinstate_stored_time;
    }

    return [
      200,
      [ 'Content-type' => 'application/json' ],
      [ $JSON->encode({ value => { now => Moonpig->env->now->epoch } }) ],
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
      my $do_method = ($req->method eq 'GET' || $req->method eq 'HEAD')
                    ? 'do_ro'
                    : 'do_rw';

      return Moonpig->env->storage->$do_method(sub {
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
          [ json_pack($result) ],
        ];
      });
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

package t::lib::Util;
use t::lib::TestEnv;
use strict;

use Carp qw(confess croak);

use Sub::Exporter -setup => {
  exports => [ qw(elapse) ],
};

sub elapse {
  my ($ledger, $n, $callback) = @_;
  Moonpig->env->stop_clock;
  for my $i (0 .. $n-1) {
    Moonpig->env->elapse_time(86_400);
    $ledger->heartbeat;
    $callback->($i) if $callback;
  }
}

1;

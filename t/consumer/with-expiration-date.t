use strict;
use warnings;

use Moonpig::Util -all;
use Test::Fatal;
use Test::More;
use Test::Routine;
use Test::Routine::Util;

use Moonpig::Context::Test -all, '$Context';

my $CLASS = class('Consumer::WithExpirationDate');
my $XID = "narf";

has ledger => (
  is   => 'rw',
  does => 'Moonpig::Role::Ledger',
  default => sub { $_[0]->test_ledger() },
);
sub ledger;  # Work around bug in Moose 'requires';

with ('t::lib::Factory::Ledger',
     );

sub jan {
  my ($dy) = @_;
  return Moonpig::DateTime->new(
    year => 2000, month => 1, day => $dy,
  );
}

my ($ledger, $consumer);
before 'run_test' => sub {
  my ($self) = @_;
  Moonpig->env->stop_clock_at(jan(1));
  $ledger = $self->test_ledger;
  $consumer = $ledger->add_consumer($CLASS,
                                    { expire_date => jan(3),
                                      xid => $XID,
                                    }
                                   );
  $ledger->mark_consumer_active__($consumer);
};

test "no replacement" => sub {
  is($consumer->replacement_mri->as_string, "moonpig://nothing",
     "replacement: nothing");
  is($ledger->active_consumer_for_xid($XID), $consumer,
     "Set up active consumer for this xid");
};

test "cannot set replacement" => sub {
  isnt(exception {
    $ledger->add_consumer($CLASS,
                          { expire_date => jan(3),
                            xid => $XID,
                            replacement_mri =>
                              Moonpig::URI->new("moonpig://something"),
                          })},
       undef,
       "specify replacement at build time");
  isnt(exception {
    $consumer->replacement_mri(Moonpig::URI->new("moonpig://something"))},
       undef,
       "specify replacement after build time");
  is($consumer->replacement_mri->as_string, "moonpig://nothing",
     "replacement: nothing");
};

test "expiration" => sub {
  plan tests => 4 + 2;
  for my $day (1 .. 4) {
    Moonpig->env->stop_clock_at(jan($day));
    $ledger->handle_event(event('heartbeat'));
    ok(($day < 3 xor $consumer->is_expired), "expired on day $day?")
  }
  is($consumer->replacement_mri->as_string, "moonpig://nothing",
     "replacement: still nothing");
  is($ledger->active_consumer_for_xid($XID), undef,
     "No longer active consumer for this xid?");
};

run_me;
done_testing;

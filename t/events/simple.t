use Test::Routine;
use Test::Routine::Util;

use Test::More;
use Test::Fatal;
use Test::Deep qw(cmp_deeply ignore superhashof);

use t::lib::Class::Ledger::ImplicitEvents;

with(
  't::lib::Factory::Ledger',
  't::lib::Factory::EventHandler',
);

test generic_event_test => sub {
  my ($self) = @_;

  my $ledger = $self->test_ledger;

  my $noop_h = $self->make_event_handler(Noop => { });

  my @calls;
  my $code_h = $self->make_event_handler(Callback => {
    code => sub {
      push @calls, [ @_ ];
    },
  });

  $ledger->register_event_handler('test.noop', 'nothing',  $noop_h);

  $ledger->register_event_handler('test.code', 'callback', $code_h);

  $ledger->register_event_handler('test.both', 'nothing',  $noop_h);
  $ledger->register_event_handler('test.both', 'callback', $code_h);

  $ledger->handle_event('test.noop', { foo => 1 });

  $ledger->handle_event('test.code', { foo => 2 });

  $ledger->handle_event('test.both', { foo => 3 });

  cmp_deeply(
    \@calls,
    [
      [ ignore(), 'test.code', superhashof({ parameters => { foo => 2 } }) ],
      [ ignore(), 'test.both', superhashof({ parameters => { foo => 3 } }) ],
    ],
    "event handler callback-handler called as expected",
  );

  isnt(
    exception { $ledger->handle_event('test.unknown', { foo => 1 }) },
    undef,
    "receiving an unknown event is fatal",
  );
};

test implicit_events_and_overrides => sub {
  my ($self) = @_;

  my $ledger = $self->test_ledger('t::lib::Class::Ledger::ImplicitEvents');

  my @calls;
  my $code_h = $self->make_event_handler(Callback => {
    code => sub {
      push @calls, [ @_ ];
    },
  });

  $ledger->register_event_handler('test.code' => 'implicit.code' => $code_h);

  pass('ok');

};

run_me;
done_testing;

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

  $ledger->register_event_handler('test.code' => 'callback' => $code_h);

  # this one should be handled by the one we just registered
  $ledger->handle_event('test.code' => { foo => 1 });

  # and this one should be handled by the implicit one
  $ledger->handle_event('test.both' => { foo => 2 });

  cmp_deeply(
    \@calls,
    [ [ ignore(), 'test.code', superhashof({ parameters => { foo => 1 } }) ] ],
    "we can safely, effectively replace an implicit handler",
  );

  cmp_deeply(
    $ledger->callback_calls,
    [ [ ignore(), 'test.both', superhashof({ parameters => { foo => 2 } }) ] ],
    "the callback still handles things for which it wasn't overridden",
  );

  my $error = exception {
    $ledger->register_event_handler(
      'test.code',
      'callback', 
       $self->make_event_handler(Noop => { }),
    );
  };

  is(
    $error->ident,
    'duplicate handler',
    "we can't replace an explicit handler",
  );
};

run_me;
done_testing;

package t::lib::Class::Ledger::ImplicitEvents;
use Moose;
extends 'Moonpig::Ledger::Basic';
with 't::lib::Factory::EventHandler';

my $noop_h = __PACKAGE__->make_event_handler(Noop => { name => 'nothing' });

my @calls;
my $code_h = __PACKAGE__->make_event_handler(Callback => {
  name     => 'callback-handler',
  callback => sub {
    push @calls, [ @_ ];
  },
});

sub implicit_stuff {
  return {
    noop_h => $noop_h,
    code_h => $code_h,
    calls  => \@calls,
  };
}

sub implicit_event_handlers {
  my ($self) = @_;

  return {
    'test.noop' => [ $noop_h ],
    'test.code' => [ $code_h ],
    'test.both' => [ $noop_h, $code_h ],
  };
}

1;

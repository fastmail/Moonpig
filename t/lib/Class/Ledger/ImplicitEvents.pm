package t::lib::Class::Ledger::ImplicitEvents;
use Moose;
extends 'Moonpig::Ledger::Basic';
with 't::lib::Factory::EventHandler';

my $noop_h = __PACKAGE__->make_event_handler(Noop => { });

my @calls;
my $code_h = __PACKAGE__->make_event_handler(Callback => {
  code => sub {
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

sub callback_calls {
  $_[0]->implicit_stuff->{calls}
}

sub implicit_event_handlers {
  my ($self) = @_;

  return {
    'test.noop' => { nothing  => $noop_h },
    'test.code' => { callback => $code_h },
    'test.both' => { nothing  => $noop_h, callback => $code_h },
  };
}

1;

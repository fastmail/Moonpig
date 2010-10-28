use strict;
use warnings;

use Carp qw(confess croak);
use Test::Routine;
use Test::More;
use Test::Routine::Util;
use Moonpig::Consumer::ByTime;
use Moonpig::Events::Handler::Callback;

use Try::Tiny;

with 't::lib::Factory::Ledger';


use Moonpig::Util -all;

# todo: warning if no bank
#       suicide
#       create successor
#       hand off to successor

test "constructor" => sub {
  my ($self) = @_;
  plan tests => 2;
  my $ld = $self->test_ledger;

  try {
    # Missing attributes
    Moonpig::Consumer::ByTime->new({ledger => $self->test_ledger});
  } finally {
    ok(@_, "missing attrs");
  };

  my $c = Moonpig::Consumer::ByTime->new({
    ledger => $self->test_ledger,
    cost_amount => dollars(1),
    cost_period => 1,
    min_balance => dollars(0),

  });
  ok($c);
};

sub queue_handler {
  my ($name, $queue) = @_;
  $queue ||= [];
  return Moonpig::Events::Handler::Callback->new(
    code => sub {
      my ($target, $evname, $args) = @_;
      push @$queue, [ $target, $evname, $args->{parameters} ];
    },
   );
}

test "warnings" => sub {
  my ($self) = @_;
  my %c_args = (
    cost_amount => dollars(1),
    cost_period => 1,
    min_balance => dollars(0),
  );

  plan tests => 1;
  my $ld = $self->test_ledger;
  my $b = Moonpig::Bank::Basic->new({ledger => $ld, amount => 1000});

  my $c = Moonpig::Consumer::ByTime->new({
    ledger => $self->test_ledger,
    bank => $b,
    %c_args,
  });

  my @eq;
  $c->register_event_handler('heart', 'hearthandler', queue_handler("c", \@eq));
  $c->handle_event('heart', { noise => 'thumpa' });
  is_deeply(\@eq, [ [ $c, 'heart', { noise => 'thumpa' } ] ]);
};

run_me;
done_testing;

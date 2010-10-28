use strict;
use warnings;

use Carp qw(confess croak);
use DateTime;
use Test::Routine;
use Test::More;
use Test::Routine::Util;
use Moonpig::Consumer::ByTime;
use Moonpig::Events::Handler::Callback;

use Try::Tiny;

with 't::lib::Factory::Ledger';

# canned args for a consumer that costs one dollar per day
my %c_args = (
    cost_amount => dollars(1),
    cost_period => DateTime::Duration->new( days => 1 ),
    min_balance => dollars(0),
);

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
    %c_args,
  });
  ok($c);
};


test expire_date => sub {
  my ($self) = @_;
  plan tests => 2;
  my $ledger = $self->test_ledger;

  my $b = Moonpig::Bank::Basic->new({
    ledger => $ledger,
    amount => dollars(3)
   });

  {
    my $c = Moonpig::Consumer::ByTime->new({
      ledger => $ledger,
      bank => $b,
      %c_args,
    });
    my $exp = $c->expire_date;
    is($exp->ymd, DateTime->from_epoch(epoch => time() + 3 * 86_400)->ymd,
       "stock consumer expires in three days");
  }

  {
    my $c = Moonpig::Consumer::ByTime->new({
      ledger => $ledger,
      bank => $b,
      current_time =>
	DateTime->new( year => 1969,
		       month => 4,
		       day => 2,
		       hour => 2,
		       minute => 38,
		       second => 0,
		      ),
      %c_args,
    });

    my $exp = $c->expire_date;
    is($exp->ymd, "1969-04-05",
       "hippie consumer expires in three days");
  }

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

test "basic_event" => sub {
  my ($self) = @_;
  plan tests => 1;
  my $ld = $self->test_ledger;

  my $c = Moonpig::Consumer::ByTime->new({
    ledger => $self->test_ledger,
    %c_args,
  });

  my @eq;
  $c->register_event_handler('heart', 'hearthandler', queue_handler("c", \@eq));
  $c->handle_event('heart', { noise => 'thumpa' });
  is_deeply(\@eq, [ [ $c, 'heart', { noise => 'thumpa' } ] ]);
};

# to do:
#  normal behavior without bank: send warnings
#  normal behavior with bank: setup replacement
#  missed heartbeat
#  extra heartbeat

test "no_bank" => sub {
  my ($self) = @_;

  plan tests => 1;
  my $ld = $self->test_ledger;
  my $b = Moonpig::Bank::Basic->new({ledger => $ld, amount => dollars(3)});

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

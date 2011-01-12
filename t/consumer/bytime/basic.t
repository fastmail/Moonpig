use strict;
use warnings;

use Carp qw(confess croak);
use DateTime;
use Moonpig::Consumer::ByTime;
use Moonpig::Events::Handler::Code;
use Moonpig::Util -all;
use Test::Deep qw(cmp_deeply);
use Test::Fatal;
use Test::More;
use Test::Routine;
use Test::Routine::Util;
use Try::Tiny;

use Moonpig::Bank::Basic;

my $CLASS = "Moonpig::Consumer::ByTime";

has ledger => (
  is   => 'rw',
  does => 'Moonpig::Role::Ledger',
  default => sub { $_[0]->test_ledger() },
);
sub ledger;  # Work around bug in Moose 'requires';

with ('t::lib::Factory::Consumers',
      't::lib::Factory::Ledger',
     );

# todo: warning if no bank
#       suicide
#       create successor
#       hand off to successor

test "constructor" => sub {
  my ($self) = @_;
  plan tests => 2;
  my $ld = $self->test_ledger;

  ok(
    exception {
      Moonpig::Consumer::ByTime->new({ledger => $self->test_ledger});
    },
    "missing attrs",
  );

  my $c = $self->test_consumer($CLASS);
  ok($c);
};

# Need more expiration date tests
test expire_date => sub {
  my ($self) = @_;
  plan tests => 4;
  my $ledger = $self->test_ledger;

  my $b = class('Bank')->new({
    ledger => $ledger,
    amount => dollars(3)
   });

  {
    my $c = $self->test_consumer($CLASS, { bank => $b, ledger => $ledger });
    my $exp = $c->expire_date;
    is($exp->ymd, DateTime->from_epoch(epoch => time() + 3 * 86_400)->ymd,
       "stock consumer expires in three days");
  }

  {
    my $c = $self->test_consumer(
      $CLASS,
      { bank => $b,
        ledger => $ledger,
        cost_amount => dollars(3),
      });
    my $exp = $c->expire_date;
    is($exp->ymd, DateTime->from_epoch(epoch => time() + 1 * 86_400)->ymd,
       "three dollars a day expires in one day");
  }

  {
    my $c = $self->test_consumer(
      $CLASS,
      { bank => $b,
        ledger => $ledger,
        cost_period => days(7),
      });

    my $exp = $c->expire_date;
    is($exp->ymd, DateTime->from_epoch(epoch => time() + 21 * 86_400)->ymd,
       "a dollar a week expires in 21 days");
  }

  {
    Moonpig->env->current_time(Moonpig::DateTime->new(
      year => 1969,
      month => 4,
      day => 2,
      hour => 2,
      minute => 38,
      second => 0,
    ));
    my $c = $self->test_consumer(
      $CLASS,
      { bank => $b,
        ledger => $ledger,
      });

    my $exp = $c->expire_date;
    is($exp->ymd, "1969-04-05",
       "hippie consumer expires in three days");
  }

};

sub queue_handler {
  my ($name, $queue) = @_;
  $queue ||= [];
  return Moonpig::Events::Handler::Code->new(
    code => sub {
      my ($receiver, $event, $args, $handler) = @_;
      push @$queue, [ $receiver, $event->ident, $event->payload ];
    },
   );
}

test "basic_event" => sub {
  my ($self) = @_;
  plan tests => 1;
  my $ld = $self->test_ledger;

  my $c = $self->test_consumer(
    $CLASS, { ledger => $self->test_ledger });

  my @eq;
  $c->register_event_handler('heart', 'hearthandler', queue_handler("c", \@eq));
  $c->handle_event(event('heart', { noise => 'thumpa' }));
  cmp_deeply(\@eq, [ [ $c, 'heart',
                       { noise => 'thumpa',
                         timestamp => Test::Deep::isa('DateTime'),
                        } ] ]);
};

run_me;
done_testing;

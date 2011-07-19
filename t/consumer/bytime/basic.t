use strict;
use warnings;

use Carp qw(confess croak);
use DateTime;
use Moonpig::Events::Handler::Code;
use Moonpig::Util -all;
use Test::Deep qw(cmp_deeply);
use Test::Fatal;
use Test::More;
use Test::Routine;
use Test::Routine::Util;
use Try::Tiny;

use Moonpig::Context::Test -all, '$Context';

my $CLASS = "Consumer::ByTime::FixedCost";
my $___ = class($CLASS); # Load it

use t::lib::Factory qw(build);

# todo: warning if no bank
#       suicide
#       create successor
#       hand off to successor

test "constructor_a" => sub {
  my ($self) = @_;
  plan tests => 1;

  my $stuff = build();

  ok(
    exception {
      $CLASS->new({
        ledger             => $stuff->{ledger},
       });
    },
    "missing attrs",
  );
};

sub setup {
  my ($self, $c_extra) = @_;
  $c_extra ||= {};

  return build(
    consumer => { class => $CLASS,
                  cost_amount        => dollars(1),
                  cost_period        => days(1),
                  old_age            => days(0),
                  replacement_mri    => Moonpig::URI->nothing(),
                  charge_description => "test consumer",
                  bank               => dollars(3),
                  make_active        => 1,
                  %$c_extra,
                });
}

test "constructor_b" => sub {
  my ($self) = @_;
  plan tests => 1;
  my $stuff = $self->setup();
  ok($stuff->{consumer});
};

# Need more expiration date tests
test expire_date => sub {
  my ($self) = @_;
  plan tests => 4;

  {
    my $stuff = $self->setup;
    my $exp = $stuff->{consumer}->expire_date;
    is($exp->ymd, DateTime->from_epoch(epoch => time() + 3 * 86_400)->ymd,
       "stock consumer expires in three days");
  }

  {
    my $stuff = $self->setup({
      cost_amount      => dollars(3),
    });
    my $exp = $stuff->{consumer}->expire_date;
    is($exp->ymd, DateTime->from_epoch(epoch => time() + 1 * 86_400)->ymd,
       "three dollars a day expires in one day");
  }

  {
    my $stuff = $self->setup({
      cost_period        => days(7),
    });

    my $exp = $stuff->{consumer}->expire_date;
    is($exp->ymd, DateTime->from_epoch(epoch => time() + 21 * 86_400)->ymd,
       "a dollar a week expires in 21 days");
  }

  {
    Moonpig->env->stop_clock_at(
      Moonpig::DateTime->new(
        year   => 1969,
        month  => 4,
        day    => 2,
        hour   => 2,
        minute => 38,
        second => 0,
       ));

    my $stuff = $self->setup();

    my $exp = $stuff->{consumer}->expire_date;
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

  my $stuff = $self->setup({
    cost_amount        => dollars(1),
  });
  my $c = $stuff->{consumer};

  my @eq;
  $c->register_event_handler('test', 'testhandler', queue_handler("c", \@eq));
  $c->handle_event(event('test', { noise => 'thumpa' }));
  cmp_deeply(\@eq, [ [ $c, 'test',
                       { noise => 'thumpa',
                         timestamp => Test::Deep::isa('DateTime'),
                        } ] ]);
};

run_me;
done_testing;

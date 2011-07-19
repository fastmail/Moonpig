use Test::Routine;

use Moonpig::Env::Test;
use t::lib::Logger '$Logger';

use Moonpig::Context::Test '-all', '$Context';

use Carp qw(confess croak);
use DateTime;
use Moonpig::Events::Handler::Code;
use Moonpig::Util -all;
use Test::Deep qw(cmp_deeply);
use Test::Fatal;
use Test::More;
use Test::Routine::Util;
use Try::Tiny;

my $CLASS = class('Consumer::FixedExpiration');

has ledger => (
  is   => 'rw',
  does => 'Moonpig::Role::Ledger',
  default => sub { $_[0]->test_ledger() },
);
sub ledger;  # Work around bug in Moose 'requires';

with ('t::lib::Factory::Consumers',
      't::lib::Factory::Ledger',
      't::lib::Role::UsesStorage',
     );

test "fixed-expiration consumer" => sub {
  my ($self) = @_;

  Moonpig->env->storage->do_rw(sub {
    Moonpig->env->stop_clock;
    my $expire_date = Moonpig->env->now + days(30);

    my $cost = dollars(1);
    my $c = $self->test_consumer(
      $CLASS,
      {
        cost_amount => $cost,
        old_age     => days(0), # lame
        charge_tags => [ qw(bogus) ],
        description => 'test fixed expiration consumer',
        expire_date => $expire_date,
        replacement_mri    => Moonpig::URI->nothing(),
      },
    );

    my $ledger = $c->ledger;

    isa_ok($c, $CLASS);

    my $invoice = $ledger->current_invoice;
    is($invoice->total_amount, $cost, "made an invoice for whole amount");

    $ledger->handle_event( event('heartbeat') );

    my $credit = $ledger->add_credit(
      class(qw(Credit::Simulated)),
      {
        amount => $cost,
      },
    );

    $ledger->process_credits;

    is($c->expire_date, $expire_date, "expire date is as created");

    Moonpig->env->elapse_time( days(20) );

    $ledger->handle_event( event('heartbeat') );

    ok( ! $c->is_expired, "consumer has not expired after 20 days");

    is($c->bank->unapplied_amount, dollars(1), "full payment remains in bank");

    Moonpig->env->elapse_time( days(120) );

    $ledger->handle_event( event('heartbeat') );

    ok(   $c->is_expired, "consumer has expired after 40 days");

    is($c->bank->unapplied_amount, 0, "bank is now empty");
  });
};

run_me;
done_testing;

#!/usr/bin/env perl
use Test::Routine;
use Test::Routine::Util -all;
use Test::More;

with(
  't::lib::Factory::Ledger',
  't::lib::Role::UsesStorage',
);

has ledger => (
  is   => 'rw',
  does => 'Moonpig::Role::Ledger',
);

use Moonpig::Env::Test;
use Moonpig::Events::Handler::Code;

use Moonpig::Util qw(class days event);

use t::lib::ConsumerTemplateSet::Demo;

use namespace::autoclean;

test "check amounts" => sub {
  my ($self) = @_;

  Moonpig->env->stop_clock;

  my $ledger = $self->test_ledger;
  $self->ledger( $ledger );

  my $consumer = $ledger->add_consumer_from_template(
    'demo-service',
    {
      xid                => "test:thing:xid",
      make_active        => 1,
    },
  );

  my $inv;
  Moonpig->env->storage->do_rw(
    sub {
      do {
        $ledger->handle_event( event('heartbeat') );
        Moonpig->env->elapse_time(days(1));
      } until $inv = $self->payable_invoice;
    });
  my $amount = $inv->total_amount;
  note "Found invoice for amount $amount; paying\n";

  Moonpig->env->storage->do_rw(
    sub {
      $ledger->add_credit(
        class(qw(Credit::Simulated)),
        { amount => $amount },
       );
      $ledger->process_credits;
    });

  ok($inv->is_paid, "invoice paid");
  my $bank = $consumer->bank;
  ok($bank, "bank exists");
  is($bank->amount, $amount, "bank for correct amount");
};

sub payable_invoice {
  my ($self) = @_;
  my ($inv) = grep { ! $_->is_open and ! $_->is_paid }
    $self->ledger->invoices;
  return $inv;
}

run_me;
done_testing;

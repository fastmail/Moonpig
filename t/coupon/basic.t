use 5.12.0;
use warnings;

use Carp qw(confess croak);
use Moonpig::Util qw(class days dollars months to_dollars years);
use Test::More;
use Test::Routine;
use Test::Routine::Util;

use t::lib::TestEnv;

use Moonpig::Test::Factory qw(do_with_fresh_ledger);

with ('Moonpig::Test::Role::UsesStorage');

Moonpig->env->stop_clock;

sub set_up_consumer {
  my ($self, $ledger) = @_;
  my $coupon_desc =  [ class("Coupon::FixedPercentage", "Coupon::Universal"),
                       { discount_rate => 0.25,
                         description => "Joe's discount",
                       }] ;

  my $consumer = $ledger->add_consumer_from_template("yearly",
                                                     { xid => "test:A",
                                                       coupon_descs => [ $coupon_desc ],
                                                       charge_description => "with coupon",
                                                       grace_period_duration => 0,
                                                     });
  my $amount = dollars(75);
  my $cred = $ledger->add_credit(class('Credit::Simulated'),
                                 { amount => $amount });
  $ledger->create_transfer({
      type   => 'consumer_funding',
      from   => $cred,
      to     => $consumer,
      amount => $amount,
    });
  die unless $consumer->is_funded;
  $consumer->become_active;
  return $consumer;
}

test "consumer setup" => sub {
  my ($self) = @_;
  do_with_fresh_ledger({},
    sub {
      my ($ledger) = @_;
      my ($consumer) = $self->set_up_consumer($ledger);
      is(@{$consumer->coupon_array}, 1, "consumer has a coupon");
      my @charges = $ledger->current_invoice->all_charges;
      is(@charges, 1, "one charge");
#      is(@charges, 2, "two charges (1 + 1 line item)");

      is($charges[0]->amount, dollars(75), "true charge amount: \$75");
      SKIP: { skip "line items unimplemented", 2;
        is($charges[1]->amount, 0, "line item amount: 0mc");
        like($charges[1]->description, qr/Joe's discount/, "line item description");
        like($charges[1]->description, qr/25%/, "line item description amount");
      }
    });
};

test "consumer journal charging" => sub {
  my ($self) = @_;
  do_with_fresh_ledger({ n => { template => "yearly",
                                xid => "test:B",
                                bank => dollars(100),
                                charge_description => "without coupon",
                                make_active => 1,
                                grace_period_duration => 0,
                              }
                        },
    sub {
      my ($ledger) = @_;
      my ($without) = $ledger->get_component("n");
      die unless $without->is_funded;
      my ($with) = $self->set_up_consumer($ledger);
      die unless $with->is_funded;
      Moonpig->env->elapse_time( days(1/2) );
      $ledger->heartbeat;
      my @j_charges = sort { $a->amount <=> $b->amount } $ledger->current_journal->all_charges;
      is(@j_charges, 2, "two journal charges");
      cmp_ok($j_charges[0]->amount, '==', int($j_charges[1]->amount * 0.75),
             "Coupon consumer charged 25% less.");
    });
};

run_me;
done_testing;

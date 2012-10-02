use 5.12.0;
use warnings;

use Carp qw(confess croak);
use Moonpig::Util qw(class days dollars months to_dollars years);
use Test::More;
use Test::Routine;
use Test::Routine::Util;

use t::lib::TestEnv;

use Moonpig::Test::Factory qw(do_with_fresh_ledger);

with ('Moonpig::Test::Role::LedgerTester');

Moonpig->env->stop_clock;

my $discount_tag = "discount-tag";

sub has_tag {
  my ($tag, $charge) = @_;
  grep $_ eq $tag, $charge->taglist;
}

sub set_up_consumer {
  my ($self, $ledger) = @_;

  my $discount = class("Discount::FixedPercentage", "Discount::RequiredTags")->new({
    discount_rate => 0.25,
    description => "Joe's discount",
    ledger => $ledger,
    tags => [ $discount_tag ],
    target_tags => [ 'test:A' ]
  });

  $ledger->add_this_discount($discount);

  my $consumer = $ledger->add_consumer_from_template(
    "yearly",
    { xid => "test:A",
      charge_description => "with discount",
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

      my @discounts = $ledger->discounts;
      is(@discounts, 1, "ledger has a discount");

      my @charges = $ledger->current_invoice->all_charges;
      is(@charges, 1, "one charge");
#      is(@charges, 2, "two charges (1 + 1 line item)");

      is($charges[0]->amount, dollars(75), "true charge amount: \$75");
      ok(
        has_tag($discount_tag, $charges[0]),
        "invoice charge contains correct tag",
      );

      SKIP: { skip "line items unimplemented", 3;
        is($charges[1]->amount, 0, "line item amount: 0mc");
        like(
          $charges[1]->description,
          qr/Joe's discount/,
          "line item description",
        );
        like(
          $charges[1]->description,
          qr/25%/,
          "line item description amount"
        );
        ok(has_tag($discount_tag, $charges[1]), "line item contains correct tag");
      }
    });
};

test "consumer journal charging" => sub {
  my ($self) = @_;
  do_with_fresh_ledger({ n => { template => "yearly",
                                xid => "test:B",
                                charge_description => "without discount",
                                make_active => 1,
                                grace_period_duration => 0,
                              }
                        },
    sub {
      my ($ledger) = @_;

      $ledger->perform_dunning;
      $self->pay_amount_due($ledger, dollars(100));
      $self->assert_n_deliveries(1, "first invoice");

      my ($without) = $ledger->get_component("n");
      die unless $without->is_funded;
      my ($with) = $self->set_up_consumer($ledger);
      die unless $with->is_funded;
      Moonpig->env->elapse_time( days(1/2) );
      $ledger->heartbeat;
      $self->assert_n_deliveries(1, "second invoice");
      my @j_charges = sort { $a->amount <=> $b->amount }
                      $ledger->current_journal->all_charges;
      is(@j_charges, 2, "two journal charges");

      cmp_ok(
        $j_charges[0]->amount,
        '==',
        $j_charges[1]->amount - int($j_charges[1]->amount * 0.25),
        "discount consumer charged 25% less.",
      );
      ok(
        has_tag($discount_tag, $j_charges[0]),
        "journal charge contains correct tag",
      );
      ok(! has_tag($discount_tag, $j_charges[1]), "sanity check");
    }
  );
};

test "required tags" => sub {
  local $TODO = "todo";
  fail();
};

run_me;
done_testing;

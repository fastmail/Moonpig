use 5.12.0;
use warnings;

use Carp qw(confess croak);
use Moonpig::Util qw(class days dollars months to_dollars years);
use Test::More;
use Test::Routine;
use Test::Routine::Util;

use t::lib::TestEnv;

use Moonpig::Test::Factory qw(do_with_fresh_ledger build_consumers);

with ('Moonpig::Test::Role::UsesStorage');

Moonpig->env->stop_clock;

test "consumer journal charging" => sub {
  my ($self) = @_;
  do_with_fresh_ledger(
    # We'll set up the consumers later.  We need to get the coupons in place
    # first so that the invoice charges are not affected by the coupons. --
    # rjbs, 2012-06-27
    { },
    sub {
      my ($ledger) = @_;

      my $coupon_A = class(qw(
        Coupon::FixedPercentage
        Coupon::RequiredTags
        Coupon::CombiningDiscount
      ))->new({
        discount_rate => 0.30,
        description   => "30% big spender discount",
        ledger        => $ledger,
        target_tags   => [ 'big-spender' ],
        combining_discount_key => 'combine',
      });

      $ledger->add_this_coupon($coupon_A);

      my $coupon_B = class(qw(
        Coupon::FixedPercentage
        Coupon::RequiredTags
        Coupon::CombiningDiscount
      ))->new({
        discount_rate => 0.20,
        description   => "20% pathetic loser discount",
        ledger        => $ledger,
        target_tags   => [ 'pathetic-loser' ],
        combining_discount_key => 'combine',
      });

      $ledger->add_this_coupon($coupon_B);

      my $coupon_C = class(qw(
        Coupon::FixedPercentage
        Coupon::RequiredTags
      ))->new({
        discount_rate => 0.10,
        description   => "10% family discount",
        ledger        => $ledger,
        target_tags   => [ 'family' ],
      });

      $ledger->add_this_coupon($coupon_C);

      build_consumers($ledger, {
        C0 => {
          template    => "yearly",
          xid         => "C0",
          bank        => dollars(100),
          make_active => 1,
          grace_period_duration => 0,
        },
        C1 => {
          template    => "yearly",
          xid         => "C1",
          bank        => dollars(100),
          make_active => 1,
          grace_period_duration => 0,
          extra_charge_tags     => [ qw( big-spender pathetic-loser ) ],
        },
        C2 => {
          template    => "yearly",
          xid         => "C2",
          bank        => dollars(100),
          make_active => 1,
          grace_period_duration => 0,
          extra_charge_tags     => [ qw( big-spender pathetic-loser family ) ],
        },
        C3 => {
          template    => "yearly",
          xid         => "C3",
          bank        => dollars(100),
          make_active => 1,
          grace_period_duration => 0,
          extra_charge_tags     => [ qw( big-spender family ) ],
        },
      });

      Moonpig->env->elapse_time( days(1/2) );
      $ledger->heartbeat;

      my $c0 = $ledger->get_component('C0');
      my $c1 = $ledger->get_component('C1');
      my $c2 = $ledger->get_component('C2');
      my $c3 = $ledger->get_component('C3');

      my @j_charges = $ledger->current_journal->all_charges;
      is(@j_charges, 4, "we charged the journal 4x");

      my @i_charges = ($ledger->payable_invoices)[0]->all_charges;
      is(@i_charges, 4, "we charged the invoice 4x");

      for my $test (
        [ journal => \@j_charges ],
        [ invoice => \@i_charges ],
      ) {
        my ($which, $items) = @$test;

        my %charge_for = map { ($_->taglist)[0] => $_ } @$items;

        my $baseline = $charge_for{C0}->amount;

        my %discount = (
          AB  => $baseline * .50, # combine( 0.3, 0.2 )
          ABC => $baseline * .55, # combine( 0.3, 0.2 ), 0.1
          AC  => $baseline * .37, # 0.3, 0.1
        );

        cmp_ok(
          abs($charge_for{C1}->amount - ($baseline - $discount{AB})),
          '<=',
          1,
          "$which charge: C1 gets 50% discount"
        ) or diag "actual ratio: " . $charge_for{C1}->amount/$baseline;

        cmp_ok(
          abs($charge_for{C2}->amount - ($baseline - $discount{ABC})),
          '<=',
          1,
          "$which charge: C2 gets 55% discount"
        ) or diag "actual ratio: " . $charge_for{C2}->amount/$baseline;

        cmp_ok(
          abs($charge_for{C3}->amount - ($baseline - $discount{AC})),
          '<=',
          1,
          "$which charge: C3 gets 37% discount"
        ) or diag "actual ratio: " . $charge_for{C3}->amount/$baseline;
      }
    }
  );
};

run_me;
done_testing;

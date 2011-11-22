use strict;
use warnings;

use Carp qw(confess croak);
use Moonpig::Util qw(class days dollars event percent sum);
use Test::More;
use Test::Routine;
use Test::Routine::Util;

use t::lib::TestEnv;

use Moonpig::Test::Factory qw(do_with_fresh_ledger);

use t::lib::Util qw(elapse);

with ('Moonpig::Test::Role::UsesStorage');

sub set_up {
  my $guid = do_with_fresh_ledger({ consumer => { template => 'dummy' }}, sub {
    my ($L) = @_;

    for (1..5) {
      $L->add_coupon(class("Coupon::FixedAmount", "Coupon::Universal"),
                     { flat_discount_amount => dollars(10),
                       description => '$10 off',
                     });
    }
    for (1..5) {
      $L->add_coupon(class("Coupon::FixedPercentage", "Coupon::Universal"),
                     { discount_rate => percent(10),
                       description => '10% off',
                     });
    }
    return $L->guid;
  });
}

test "order" => sub {
  my $guid;

  # keep trying until we get some of the coupons out of order
  { my @c;
    do {
      Moonpig->env->storage->do_with_ledger(set_up(), sub {
        my ($ledger) = @_;
        @c = $ledger->coupons;
        $guid = $ledger->guid;
      })
    } until (grep $_->does("Moonpig::Role::Coupon::FixedAmount"), @c[0..4]);
  }

  Moonpig->env->storage->do_with_ledger($guid, sub {
    my ($L) = @_;
    my @c = $L->coupons;
    is(@c, 10, "created ten assorted coupons");

    my $inv = $L->current_invoice;
    $inv->add_charge(
      class( "InvoiceCharge" )->new({
        description => "One hundred assorted fruit pies",
        amount      => dollars(100),
        tags        => [],
        consumer    => $L->get_component('consumer'),
      }));

    until ($L->payable_invoices) {
      elapse($L, 1);
    }

    is($L->credits, 0, "no credits yet");
    $L->process_credits;
    ok ($inv->is_paid, "invoice was paid");
    is($L->credits, 10, "each coupon made a credit");
    for my $c ($L->credits) {
      is($c->unapplied_amount, 0, "credit fully applied");
    }
  });
};

run_me;
done_testing;

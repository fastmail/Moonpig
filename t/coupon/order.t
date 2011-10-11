use strict;
use warnings;

use Carp qw(confess croak);
use Moonpig::Util qw(class days dollars event percent sum);
use Test::More;
use Test::Routine;
use Test::Routine::Util;

use Moonpig::Test::Factory qw(build);
use t::lib::Util qw(elapse);

use Moonpig::Context::Test -all, '$Context';
with ('t::lib::Role::UsesStorage');

sub set_up {
  my $stuff = build();
  my $L = $stuff->{ledger};

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
  return $stuff;
}

test "order" => sub {
  my $stuff;

  # keep trying until we get some of the coupons out of order
  { my @c;
    do {
      $stuff = set_up();
      @c = $stuff->{ledger}->coupons;
    } until (grep $_->does("Moonpig::Role::Coupon::FixedAmount"), @c[0..4]);
  }

  my $L = $stuff->{ledger};
  {
    my @c = $L->coupons;
    is(@c, 10, "created ten assorted coupons");
  }

  my $inv = $L->current_invoice;
  $inv->add_charge(
    class( "InvoiceCharge" )->new({
      description => "One hundred assorted fruit pies",
      amount      => dollars(100),
      tags        => [],
    }));

  until ($L->payable_invoices) {
    Moonpig->env->storage->do_rw(sub { elapse($L, 1) });
  }

  is($L->credits, 0, "no credits yet");
  $L->process_credits;
  ok ($inv->is_paid, "invoice was paid");
  is($L->credits, 10, "each coupon made a credit");
  for my $c ($L->credits) {
    is($c->unapplied_amount, 0, "credit fully applied");
  }
};

run_me;
done_testing;

use strict;
use warnings;

use Carp qw(confess croak);
use Moonpig::Util qw(class days dollars event sum);
use Test::More;
use Test::Routine;
use Test::Routine::Util;

use Moonpig::Test::Factory qw(build);
use t::lib::Util qw(elapse);

use Moonpig::Context::Test -all, '$Context';

with ('t::lib::Role::UsesStorage');

before run_test => sub {
  Moonpig->env->reset_clock;
};

sub pay_unpaid_invoices {
  my ($self, $ledger) = @_;
  my $total = 0;

  Moonpig->env->stop_clock();
  until ($ledger->payable_invoices) {
    Moonpig->env->elapse_time(days(1));
    Moonpig->env->storage->do_rw(sub {
                                   $ledger->handle_event( event('heartbeat') );
                                 });
  }

  for my $invoice ($ledger->invoices) {
    $total += $invoice->total_amount unless $invoice->is_paid;
  }
  printf "# Total amount payable: %.2f\n", $total / 100000;
  $ledger->process_credits;
}

sub try_coupon {
  my ($self, $non_profit, $total_discount) = @_;

  my $base_cost_amount = dollars(100);
  my $cost_amount = $base_cost_amount;
  $cost_amount *= 0.9 if $non_profit;
  my $coupon_discount = $total_discount - ($base_cost_amount - $cost_amount);

  my @x_charge_tags = ();
  push @x_charge_tags, "nonprofit" if $non_profit;

  my $stuff = build(c => { template => 'quick',
                           cost_amount => $cost_amount,
                           extra_invoice_charge_tags => \@x_charge_tags });
  my $L = $stuff->{ledger};

  $L->add_coupon(class("Coupon::BulkDiscount"),
                 { target_tags => [],
                   description => 'bulk discount for accounts',
                 });
  $L->add_credit(class('Credit::Simulated'), { amount => dollars(100) });
  $self->pay_unpaid_invoices($L);
  { my ($inv) = $L->invoices;
    ok($inv->is_paid, "invoice is paid");
  }

  {
    my @cred = $L->credits;
    is(@cred, 2, "Two credits");
    my $remaining_credit = sum map $_->unapplied_amount, @cred;

    my ($payment_cred, $coupon_cred) = $cred[0]->as_string eq "discount" ?
      @cred[1,0] : @cred[0,1];

    is ($coupon_cred->amount, $coupon_discount,
        sprintf "coupon create \$%.2f credit", $coupon_discount/100000);
    is ($coupon_cred->unapplied_amount, 0, "coupon credit used up");
    is ($payment_cred->amount, dollars(100), "paid \$100");
    is ($payment_cred->unapplied_amount, $total_discount,
        sprintf "\$%.2f left over from pmt", $total_discount/100000);
  }
}

test "bulk discount" => sub {
  my ($self) = @_;

  subtest "full (10%) bulk discount" => sub {
    $self->try_coupon(0, dollars(10));
  };

  subtest "partial (15%) bulk discount for NP accounts" => sub {
    $self->try_coupon(1, dollars(15));

  };
};

run_me;
done_testing;

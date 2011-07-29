use strict;
use warnings;

use Carp qw(confess croak);
use Moonpig::Util qw(class);
use Test::More;
use Test::Routine;
use Test::Routine::Util;

use t::lib::Factory qw(build);

my $xid = "consumer:5y:test";

sub set_up {
  my ($self) = @_;

  my $stuff = build(b5 => { template => 'fiveyear', replacement => 'g1', xid => $xid },
                    g1 => { template => 'free_sixthyear',                xid => $xid });
  return @{$stuff}{qw(ledger b5 g1)};
}

test setup => sub {
  my ($self) = @_;
  my ($ledger, $b5, $g1) = $self->set_up;

  ok($ledger);
  ok($b5);
  ok($g1);
  is($b5->replacement, $g1);
  is($ledger->active_consumer_for_xid($xid), $b5);
  ok(  $b5->is_active);
  ok(! $g1->is_active);
  ok($ledger->latest_invoice);
};

# test to make sure that coupon is properly inserted
test coupon_insertion => sub {
  my ($self) = @_;
  my ($ledger, $b5, $g1) = $self->set_up;

  $self->pay_open_invoices($ledger);
  my $coupons = $ledger->coupon_array;
  is(@$coupons, 1, "exactly one coupon");
};

sub pay_open_invoices {
  my ($self, $ledger) = @_;
  my $total = 0;
  for my $invoice ($ledger->invoices) {
    $total += $invoice->total_amount unless $invoice->is_paid;
  }
  $ledger->add_credit(class('Credit::Simulated'), { amount => $total });
  $ledger->process_credits;
}



# test to make sure that if the coupon is there, the correct amount is invoiced
# test to make sure that when the invoice is paid, the coupon is properly applied
# and the self-funding consumer is created
test coupon_payment => sub {
 TODO: {
   my ($self) = @_;
   my ($ledger, $b5, $g1) = $self->set_up;

   local $TODO = 'x';
  # is the coupon in the ledger?
    fail("not implemented");
 }

};

# test to make sure everything is cancelled on account cancellation
test cancellation => sub {
 TODO: {
    local $TODO = 'x';
    fail("not implemented");
  }
};

run_me;
done_testing;

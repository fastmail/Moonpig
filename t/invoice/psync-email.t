use strict;
use Test::Routine;
use Test::More;
use Test::Routine::Util;
use Test::Fatal;

use t::lib::TestEnv;
use Moonpig::Util qw(days dollars);
use Stick::Util qw(ppack);
use Scalar::Util qw(reftype);

plan skip_all => "psyncing is disabled in this revision";

with(
  't::lib::Factory::EventHandler',
  'Moonpig::Test::Role::LedgerTester',
);

use t::lib::ConsumerTemplateSet::Test;
use Moonpig::Test::Factory qw(do_with_fresh_ledger);

my $jan1 = Moonpig::DateTime->new( year => 2000, month => 1, day => 1 );

before run_test => sub {
  Moonpig->env->email_sender->clear_deliveries;
  Moonpig->env->stop_clock_at($jan1);
};

sub do_test (&) {
  my ($chain_length, $code) = @_;
  ($chain_length, $code) = (0, $chain_length) if ref $chain_length;

  do_with_fresh_ledger({ c => { template => 'psync' }}, sub {
    my ($ledger) = @_;
    my $c = $ledger->get_component("c");
    $c->_adjust_replacement_chain($chain_length)
      if $chain_length;
    my ($credit) = $ledger->credit_collection->add({
      type => 'Simulated',
      attributes => { amount => dollars(14) }
    });
    $ledger->name_component("credit", $credit);

    $code->($ledger, $c);
  });
}

sub get_single_delivery {
  my ($msg) = @_;
  $msg //= "exactly one delivery";
  Moonpig->env->process_email_queue;
  my $sender = Moonpig->env->email_sender;
  is(my ($delivery) = $sender->deliveries, 1, $msg);
  $sender->clear_deliveries;
  return $delivery;
}

sub body {
  my ($delivery) = @_;
  my $email = $delivery->{email} or die;
  my ($part) = grep { $_->content_type =~ m{text/plain} } $email->subparts
    or die;
  return $part->body_str;
}

sub elapse {
  my ($ledger, $days) = @_;
  $days //= 1;
  for (1 .. $days) {
    $ledger->heartbeat;
    Moonpig->env->elapse_time(86_400);
  }
}

test 'setup sanity checks' => sub {
  do_test {
    my ($ledger, $c) = @_;
    ok($c);
    ok($c->does('Moonpig::Role::Consumer::ByTime'));
    ok($c->does("t::lib::Role::Consumer::VaryingCharge"));
    is($c->_predicted_shortfall, 0, "initially no predicted shortfall");
    is($c->expected_funds({ include_unpaid_charges => 1 }), dollars(14),
       "expected funds incl unpaid");
    is($c->expected_funds({ include_unpaid_charges => 0 }), 0, "expected funds not incl unpaid");
    is($c->_estimated_remaining_funded_lifetime({ amount => dollars(14) }), days(14),
      "est lifetime 14d");

    $ledger->perform_dunning; # close the invoice and process the credit

    is($c->expected_funds({ include_unpaid_charges => 1 }), dollars(14),
       "expected funds incl unpaid");
    is($c->expected_funds({ include_unpaid_charges => 0 }), dollars(14),
       "expected funds not incl unpaid");
    is($c->unapplied_amount, dollars(14), "did not spend any money yet");
    is($c->_predicted_shortfall, 0, "initially no predicted shortfall");

    my @inv = $ledger->invoices;
    is(@inv, 1, "one invoice");
    ok($inv[0]->is_closed, "the invoice is closed");
    ok($inv[0]->is_paid, "the invoice is paid");

    my @qu = $ledger->quotes;
    is(@qu, 0, "no quotes");
  };
};

test 'single consumer' => sub {
  do_test {
    my ($ledger, $c) = @_;
    my $sender = Moonpig->env->email_sender;

    subtest "psync quote when rate changes" => sub {
      elapse($ledger,4);
      get_single_delivery("one email delivery (the invoice)");
      # Have $14-$4 = $10 after 4 days;
      # now spending $2/day => remaining lifetime = 5d
      # remaining lifetime should have been 10d
      # To top up the account, need to get $1 per remaining day = $10
      $c->total_charge_amount(dollars(28));
      is($c->_predicted_shortfall, days(5), "double charge -> shortfall 5d");
      elapse($ledger) until $ledger->quotes;
      # We now have $8 and have used up 5 days

      Moonpig->env->process_email_queue;
      my $sender = Moonpig->env->email_sender;
      my ($delivery) = get_single_delivery("one email delivery (the psync quote)");
      my $body = body($delivery);
      like($body, qr/\S/, "psync mail body is not empty");
      like($body, qr/to make payment/i, "this is the request for payment");
      like($body, qr/\$10\.00/, "found correct charge amount");
      my ($new_date) = $body =~ qr/expected to continue until\s+(\w+ [\d ]\d, \d{4})/;
      is ($new_date, "January 10, 2000", "new expiration date");
      my ($old_date) = $body =~ qr/extend service to\s+(\w+ [\d ]\d, \d{4})/;
      is ($old_date, "January 15, 2000", "old expiration date");

      my ($pay_page_url) = $body =~ m{(https://www.pobox.com/pay\?quote=[0-9A-F-]+)};
      my ($q) = $ledger->quotes;
      is($pay_page_url, "https://www.pobox.com/pay?quote=" . $q->guid, "pay url");
    };
    # We now have $8 and have used up 5 days

    subtest "psync notice when rate changes" => sub {
      $c->total_charge_amount(dollars(7)); # $.50 per day
      elapse($ledger);
      # We now have $7.50 and have used up 6 days
      my ($delivery) = get_single_delivery("one email delivery (the psync notice)");
      my $body = body($delivery);
      like($body, qr/your account price has decreased/i, "this is the nonpayment notice");
      my ($new_date) = $body =~ qr/will now expire on\s+(\w+ [\d ]\d, \d{4})/;
      is ($new_date, "January 22, 2000", "new expiration date");
      my ($old_date) = $body =~ qr/was due to expire after\s+(\w+ [\d ]\d, \d{4})/;
      is ($old_date, "January 15, 2000", "old expiration date");
    };

  };
};

run_me;
done_testing;

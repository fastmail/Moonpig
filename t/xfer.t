use Test::Routine;
use Test::More;
use Test::Routine::Util;

use Carp::Assert;
use Moonpig::Hold;
use Moonpig::Transfer;
use Moonpig::Util qw(dollars);
use Try::Tiny;

with 't::lib::Factory::Ledger';

test "basics of transfer" => sub {
  my ($self) = @_;
  plan tests => 4;

  my $ledger = $self->test_ledger;
  my ($bank, $consumer) = $self->add_bank_and_consumer_to($ledger);

  my $amount = $bank->amount;
  is(
    $amount,
    $bank->unapplied_amount,
    "we start with M $amount, total and remaining",
  );

  assert($amount > 5000, 'we have at least M 5000 in the bank');

  my @xfers;

  subtest "initial transfer" => sub {
    plan tests => 3;

    push @xfers, Moonpig::Transfer->new({
      amount => 5000,
      bank   => $bank,
      consumer => $consumer,
    });

    is(@xfers, 1, "we made a transfer");
    isa_ok($xfers[0], 'Moonpig::Transfer', "the 1st transfer");

    is(
      $bank->unapplied_amount,
      $amount - 5000,
      "the transfer has affected the apparent remaining amount",
    );
  };

  subtest "transfer down to zero" => sub {
    plan tests => 3;

    push @xfers, Moonpig::Transfer->new({
      amount => $amount - 5000,
      bank   => $bank,
      consumer => $consumer,
    });

    is(@xfers, 2, "we made a transfer");
    isa_ok($xfers[1], 'Moonpig::Transfer', "the 2nd transfer");

    is(
      $bank->unapplied_amount,
      0,
      "we've got M 0 left in our bank",
    );
  };

  subtest "transfer out of an empty bank" => sub {
    plan tests => 4;

    my $err;
    my $ok = try {
      push @xfers, Moonpig::Transfer->new({
        amount => 1,
        bank   => $bank,
        consumer => $consumer,
      });
      1;
    } catch {
      $err = $_;
      return;
    };

    ok(! $ok, "we couldn't transfer anything from an empty bank");
    like($err, qr{refusing to perform overtransfer}, "got the right error");
    is($bank->unapplied_amount, 0, "still have M 0 in bank");
    is(@xfers, 2, "the new transfer was never registered");
  };
};

test "multiple transfer types" => sub {
  my ($self) = @_;
  plan tests => 2;
  my $ledger = $self->test_ledger;
  my ($bank, $consumer) = $self->add_bank_and_consumer_to($ledger);
  my $amt = $bank->amount;

  my $h = Moonpig::Hold->new({
    consumer => $consumer,
    bank => $bank,
    amount => dollars(1),
  });
  is($bank->unapplied_amount, $amt - dollars(1), "hold for \$1");

  my $t = Moonpig::Transfer->new({
    consumer => $consumer,
    bank => $bank,
    amount => dollars(2),
  });
  is($bank->unapplied_amount, $amt - dollars(3), "transfer of \$2");
};

run_me;
done_testing;

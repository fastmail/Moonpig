use Carp::Assert;
use Moonpig::Util qw(dollars);
use Test::More;
use Test::Routine;
use Test::Routine::Util;
use Try::Tiny;

use Moonpig::Context::Test -all, '$Context';

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

    push @xfers, $ledger->transfer({
      amount   => 5000,
      from   => $bank,
      to     => $consumer,
    });

    is(@xfers, 1, "we made a transfer");
    is($xfers[0]->type, 'transfer', "the 1st transfer");

    is(
      $bank->unapplied_amount,
      $amount - 5000,
      "the transfer has affected the apparent remaining amount",
    );
  };

  subtest "transfer down to zero" => sub {
    plan tests => 3;

    push @xfers, $ledger->transfer({
      amount => $amount - 5000,
      from => $bank,
      to   => $consumer,
    });

    is(@xfers, 2, "we made a transfer");
    is($xfers[1]->type, 'transfer', "the 2nd transfer");

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
      push @xfers, $ledger->transfer({
        amount => 1,
        from => $bank,
        to   => $consumer,
      });
      1;
    } catch {
      $err = $_;
      return;
    };

    ok(! $ok, "we couldn't transfer anything from an empty bank");
    like($err, qr{Refusing overdraft transfer}, "got the right error");
    is($bank->unapplied_amount, 0, "still have M 0 in bank");
    is(@xfers, 2, "the new transfer was never registered");
  };
};

test "multiple transfer types" => sub {
  my ($self) = @_;
  plan tests => 3;
  my $ledger = $self->test_ledger;
  my ($bank, $consumer) = $self->add_bank_and_consumer_to($ledger);
  my $amt = $bank->amount;

  my $h = $ledger->create_transfer({
    type   => 'hold',
    to     => $consumer,
    from   => $bank,
    amount => dollars(1),
  });
  is($bank->unapplied_amount, $amt - dollars(1), "hold for \$1");

  my $t = $ledger->create_transfer({
    type   => 'transfer',
    to     => $consumer,
    from   => $bank,
    amount => dollars(2),
   });
  is($bank->unapplied_amount, $amt - dollars(3), "transfer of \$2");

  $h->delete();
  is($bank->unapplied_amount, $amt - dollars(2), "deleted hold");
};

test "ledger->transfer" => sub {
    my ($self) = @_;
    plan tests => 6;

    my $ledger = $self->test_ledger;
    my ($bank, $consumer) = $self->add_bank_and_consumer_to($ledger);

    for my $type (qw(transfer bank_credit DEFAULT)) {
        my $err;
        my $t = try {
           $ledger->transfer({
               amount => 1,
               from => $bank,
               to   => $consumer,
               $type eq "DEFAULT" ? () : (type => $type),
           });
        } catch {
            $err = $_;
            return;
        };
        if ($type eq "DEFAULT" || $type eq "transfer") {
            ok($t);
            is($t->type, "transfer");
        } else {
            ok(! $t);
            like($err, qr/\S+/);
        }
    }
};


run_me;
done_testing;

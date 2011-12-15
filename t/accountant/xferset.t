use Test::Routine;

use Carp qw(confess croak);
use Moonpig::DateTime;
use Moonpig::Util -all;
use Test::Deep qw(bag cmp_bag);
use Test::More;
use Test::Routine::Util;

use t::lib::TestEnv;

use Moonpig::Test::Factory qw(build);

sub jan {
  my ($day) = @_;
  Moonpig::DateTime->new( year => 2000, month => 1, day => $day );
}

my ($Ledger, %Transfers);
my (@b, @c);

sub setup {
  my ($self) = @_;

  my $stuff = build(c1 => { template => "dummy_with_bank",
                            bank => dollars(100),
                          },
                    c2 => { template => "dummy_with_bank",
                            bank => dollars(100),
                          },
                   );

  $Ledger = $stuff->{ledger};
  @c = @{$stuff}{'c1', 'c2'};
  @b = map $_->bank, @c;

  for my $b (0..1) {
    for my $c (0..1) {
      my $t = $Ledger->transfer({
        from => $b[$b],
        to => $c[$c],
        amount => 100 + $b*10 + $c,
        date => jan(10 + $b*10 + $c), # 10, 11, 20, 21
      });
      $Transfers{"$b$c"} = $t;
    }
  }
}

test "from" => sub {
  my ($self) = @_;
  my %t = %Transfers;
  cmp_bag([ $Ledger->accountant->from_bank($b[0])->all ], [ @t{"00", "01"} ]);
  cmp_bag([ $Ledger->accountant->from_bank($b[1])->all ], [ @t{"10", "11"} ]);
  cmp_bag([ $Ledger->accountant->from_consumer($c[0])->all ], [ ]);
};

test "to" => sub {
  my ($self) = @_;
  my %t = %Transfers;

  my @deposits = $Ledger->accountant->to_bank($b[0])->all;
  is(@deposits, 1, "we made 1 deposit to find the bank");

  cmp_bag([ $Ledger->accountant->to_consumer($c[0])->all ], [ @t{"10", "00"} ]);
  cmp_bag([ $Ledger->accountant->to_consumer($c[1])->all ], [ @t{"11", "01"} ]);
};


# Right now credits are the only CanTransfer that supports both
# incoming and outgoing transfers, so we'll use that to test.
#
# bank      ->     credit        ->          payable
#     bank_cashout       credit_application
test "all_for" => sub {
  my ($self) = @_;
  my $amount = dollars(1.50);

  # Bank to credit
  my $credit = $Ledger->add_credit(
    class(qw(t::Refundable::Test Credit::Courtesy)),
    {
      amount => $amount,
      reason => 'ran over your dog',
    },
  );
  my $t1 = $Ledger->create_transfer({
    type   => 'bank_cashout',
    from   => $b[0],
    to     => $credit,
    amount => $amount,
  });

  # Credit to payable
  my $refund = $credit->issue_refund;
  my $t2 = do {
    my @t = $Ledger->accountant->to_payable($refund)->all;
    is(@t, 1, "one transfer to refund object");
    $t[0];
  };

  cmp_bag([ $Ledger->accountant->all_for_credit($credit)->all ], [ $t1, $t2 ]);
  is($credit->unapplied_amount, 0, "no credit left");
};

before run_test => \&setup;

run_me;
done_testing;

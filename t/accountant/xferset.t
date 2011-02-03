
use strict;
use warnings;

use Carp qw(confess croak);
use Moonpig::DateTime;
use Moonpig::Util -all;
use Test::Deep qw(bag cmp_bag);
use Test::More;
use Test::Routine;
use Test::Routine::Util;

with ('t::lib::Factory::Ledger');

has ledger => (
  is   => 'rw',
  does => 'Moonpig::Role::Ledger',
  default => sub { $_[0]->test_ledger() },
  lazy => 1,
  clearer => 'scrub_ledger',
  handles => [ qw(accountant) ],
);

has transfers => (
  is  => 'rw',
  isa => 'HashRef',
  default => sub { {} },
  lazy => 1,
  clearer => 'scrub_transfers',
);

my (@b, @c);

sub jan {
  my ($day) = @_;
  Moonpig::DateTime->new( year => 2000, month => 1, day => $day );
}

sub scrub {
  my ($self) = @_;
  $self->scrub_ledger;
  $self->scrub_transfers;
  (@b, @c) = ();
}

sub setup {
  my ($self) = @_;
  $self->scrub;
  my ($b1, $c1) = $self->add_bank_and_consumer_to($self->ledger);
  my ($b2, $c2) = $self->add_bank_and_consumer_to($self->ledger);
  @b = ($b1, $b2);
  @c = ($c1, $c2);

  for my $b (0..1) {
    for my $c (0..1) {
      my $t = $self->ledger->transfer({
        from => $b[$b],
        to => $c[$c],
        amount => 100 + $b*10 + $c,
        date => jan(10 + $b*10 + $c), # 10, 11, 20, 21
      });
      $self->transfers->{"$b$c"} = $t;
    }
  }
}

test "from" => sub {
  my ($self) = @_;
  my %t = %{$self->transfers};
  cmp_bag([ $self->accountant->from_bank($b[0])->all ], [ @t{"00", "01"} ]);
  cmp_bag([ $self->accountant->from_bank($b[1])->all ], [ @t{"10", "11"} ]);
  cmp_bag([ $self->accountant->from_consumer($c[0])->all ], [ ]);
};

test "to" => sub {
  my ($self) = @_;
  my %t = %{$self->transfers};
  cmp_bag([ $self->accountant->to_bank($b[0])->all ], [ ]);
  cmp_bag([ $self->accountant->to_consumer($c[0])->all ], [ @t{"10", "00"} ]);
  cmp_bag([ $self->accountant->to_consumer($c[1])->all ], [ @t{"11", "01"} ]);
};


# Right now credits are the only CanTransfer that supports both
# incoming and outgoing transfers, so we'll use that to test.
#
# bank      ->     credit        ->          payable
#      bank_credit        credit_application
test "all_for" => sub {
  my ($self) = @_;
  my $amount = dollars(1.50);

  # Bank to credit
  my $credit = $self->ledger->add_credit(
    class(qw(t::Refundable::Test Credit::Courtesy)),
    {
      amount => $amount,
      reason => 'ran over your dog',
    },
  );
  my $t1 = $self->ledger->create_transfer({
    type   => 'bank_credit',
    from   => $b[0],
    to     => $credit,
    amount => $amount,
  });

  # Credit to payable
  my $refund = $credit->issue_refund;
  my $t2 = do {
    my @t = $self->accountant->to_payable($refund)->all;
    is(@t, 1, "one transfer to refund object");
    $t[0];
  };

  cmp_bag([ $self->accountant->all_for_credit($credit)->all ], [ $t1, $t2 ]);
  is($credit->unapplied_amount, 0, "no credit left");
};

before run_test => \&setup;

run_me;
done_testing;

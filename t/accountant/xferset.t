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
my (@consumers, @credits);

sub setup {
  my ($self) = @_;

  my $stuff = build(
    c0 => {
      template => "dummy",
      bank     => dollars(100),
    },
    c1 => {
      template => "dummy",
    },
  );

  $Ledger = $stuff->{ledger};

  @consumers = @{$stuff}{qw( c0 c1 )};
  @credits   = $Ledger->credits; # there will be one, xfer made to c1

  ($Transfers{funding}) = $Ledger->accountant->to_consumer($consumers[0])
                          ->all;

  $Transfers{transfer} = $Ledger->transfer({
    from => $consumers[0],
    to   => $Ledger->current_journal,
    amount => dollars(50),
    date   => jan(1),
  });
}

test "from" => sub {
  my ($self) = @_;
  my %t = %Transfers;

  cmp_bag(
    [ $Ledger->accountant->from_credit($credits[0])->all ],
    [ $t{funding} ],
    "one transfer from initial credit",
  );

  cmp_bag(
    [ $Ledger->accountant->from_consumer($consumers[0])->all ],
    [ $t{transfer} ],
    "one transfer from consumer",
  );

  cmp_bag(
    [ $Ledger->accountant->from_consumer($consumers[1])->all ],
    [ ],
    "no transfers from unfunded consumer",
  );
};

test "to" => sub {
  my ($self) = @_;
  my %t = %Transfers;

  my @deposits = $Ledger->accountant->to_consumer($consumers[0])->all;
  is(@deposits, 1, "we made 1 deposit to fund the consumer");

  cmp_bag(
    [ $Ledger->accountant->to_consumer($consumers[0])->all ],
    [ $t{funding} ],
    "we did one transfer to the funded consumer",
  );

  cmp_bag(
    [ $Ledger->accountant->to_journal($Ledger->current_journal)->all ],
    [ $t{transfer} ],
    "we find one transfer to the journal",
  );

  cmp_bag(
    [ $Ledger->accountant->to_consumer($consumers[1])->all ],
    [ ],
    "no transfers to fund the unfunded consumer",
  );
};

test "all_for" => sub {
  my ($self) = @_;
  my %t = %Transfers;

  cmp_bag(
    [ $Ledger->accountant->all_for_consumer($consumers[0])->all ],
    [ $t{funding}, $t{transfer} ],
    "there are xfers in and out of the funded consumer",
  );

  my ($in)  = $Ledger->accountant->to_consumer(  $consumers[0])->all;
  my ($out) = $Ledger->accountant->from_consumer($consumers[0])->all;

  my $remaining = $in->amount - $out->amount;

  is($remaining, dollars(50), 'we have $50 remaining');
};

before run_test => \&setup;

run_me;
done_testing;


use strict;
use warnings;

use Carp qw(confess croak);
use Moonpig::Util -all;
use Test::Exception;
use Test::More;
use Test::Routine;
use Test::Routine::Util;
use t::lib::Factory qw(build);

use Moonpig::Context::Test -all, '$Context';

my ($Ledger, $b, $c);
sub setup {
  my ($self) = @_;
  my $stuff = build(cons => { template => 'dummy_with_bank',
                              bank => dollars(100),
                            });
  ($Ledger, $b, $c) = @{$stuff}{qw(ledger cons.bank cons)};
}

# This is to test that when the hold is for more than 50% of the
# remaining funds, we can still convert it to a transfer.  Note that
# creating the transfer first and then deleting the hold won't work
# with the obvious implementation, since that will cause an overdraft.
test "get and commit hold" => sub {
  my ($self) = @_;
  plan tests => 6;
  $self->setup;
  my $amount = int($b->unapplied_amount * 0.75);
  my $x_remaining = $b->unapplied_amount - $amount;
  my $h = $Ledger->create_transfer({
    type => 'hold',
    from => $b,
    to => $c,
    amount => $amount,
  });
  ok($h);
  is($b->unapplied_amount, $x_remaining);
  my $t = $Ledger->accountant->commit_hold($h);
  ok($t);
  is($t->amount, $amount);
  is($t->type, 'transfer');
  is($b->unapplied_amount, $x_remaining);
};

run_me;
done_testing;

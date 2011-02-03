
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

has banks => (
  is  => 'rw',
  isa => 'ArrayRef',
  default => sub { [] },
  lazy => 1,
  clearer => 'scrub_banks',
);

has consumers => (
  is  => 'rw',
  isa => 'ArrayRef',
  default => sub { [] },
  lazy => 1,
  clearer => 'scrub_consumers',
);

sub jan {
  my ($day) = @_;
  Moonpig::DateTime->new( year => 2000, month => 1, day => $day );
}

sub scrub {
  my ($self) = @_;
  $self->scrub_ledger;
  $self->scrub_transfers;
  $self->scrub_banks;
  $self->scrub_consumers;
}

sub setup {
  my ($self) = @_;
  $self->scrub;
  my ($b1, $c1) = $self->add_bank_and_consumer_to($self->ledger);
  my ($b2, $c2) = $self->add_bank_and_consumer_to($self->ledger);
  push @{$self->banks}, $b1, $b2;
  push @{$self->consumers}, $c1, $c2;

  for my $b (0..1) {
    for my $c (0..1) {
      my $t = $self->ledger->transfer({
        from => $self->banks->[$b],
        to => $self->consumers->[$c],
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
  my @b = @{$self->banks};
  my @c = @{$self->consumers};
  cmp_bag([ $self->accountant->from_bank($b[0])->all ], [ @t{"00", "01"} ]);
  cmp_bag([ $self->accountant->from_bank($b[1])->all ], [ @t{"10", "11"} ]);
  cmp_bag([ $self->accountant->from_consumer($c[0])->all ], [ ]);
};

test "to" => sub {
  my ($self) = @_;
  my %t = %{$self->transfers};
  my @b = @{$self->banks};
  my @c = @{$self->consumers};
  cmp_bag([ $self->accountant->to_bank($b[0])->all ], [ ]);
  cmp_bag([ $self->accountant->to_consumer($c[0])->all ], [ @t{"10", "00"} ]);
  cmp_bag([ $self->accountant->to_consumer($c[1])->all ], [ @t{"11", "01"} ]);
};

# todo: all_for


before run_test => \&setup;

run_me;
done_testing;

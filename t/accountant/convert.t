use Test::Routine;

use Carp qw(confess croak);
use Moonpig;
use t::lib::TestEnv;
use Moonpig::Util -all;
use Test::Exception;
use Test::More;
use Test::Routine::Util;
use Moonpig::Test::Factory qw(build);

has stuff => (
  is => 'rw',
  isa => 'HashRef',
  default => sub { build(consumer => { template => 'dummy_with_bank',
                                       bank => dollars(100) } ) },
);

sub ledger { $_[0]->stuff->{ledger} }
sub accountant { $_[0]->ledger->accountant }

sub make_hold {
  my ($self) = @_;
  my $h = $self->ledger->create_transfer({
    type => 'hold',
    from => $self->stuff->{consumer},
    to   => $self->ledger->current_journal,
    amount => 1
  });
  return $h;
}

test convert_hold_to_transfer_raw => sub {
  my ($self) = @_;
  plan tests => 5;
  my $h = $self->make_hold;
  sleep 1;
  my $t = $self->accountant->_convert_transfer_type($h, 'hold' => 'transfer');
  is($t->type, 'transfer');
  cmp_ok($t->date, '!=', $h->date);
  is($t->amount, $h->amount);
  is($t->source, $h->source);
  is($t->target, $h->target);
};

test commit_hold => sub {
  my ($self) = @_;
  plan tests => 5;
  my $h = $self->make_hold;
  sleep 1;
  my $t = $self->accountant->commit_hold($h);
  is($t->type, 'transfer');
  cmp_ok($t->date, '!=', $h->date);
  is($t->amount, $h->amount);
  is($t->source, $h->source);
  is($t->target, $h->target);
};

test commit_failures => sub {
  my ($self) = @_;
  plan tests => 4;
  my $t = $self->ledger->create_transfer({
    type => "transfer",
    from => $self->stuff->{consumer},
    to   => $self->ledger->current_journal,
    amount => 1,
  });

  dies_ok { $self->accountant->
              _convert_transfer_type($t, 'transfer' => 'hold') };

  my $h = $self->ledger->create_transfer({
    type => "hold",
    from => $self->stuff->{consumer},
    to   => $self->ledger->current_journal,
    amount => 1,
  });

  dies_ok { $self->accountant->
              _convert_transfer_type($h, 'transfer' => 'hold') };
  dies_ok { $self->accountant->
              _convert_transfer_type($h, 'hold' => 'potato') };
  dies_ok { $self->accountant->
              _convert_transfer_type($h, 'hold' => 'payable') };

};

run_me;
done_testing;

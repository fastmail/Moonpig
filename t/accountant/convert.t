use Test::Routine;

use Carp qw(confess croak);
use Moonpig::Util -all;
use Test::Exception;
use Test::More;
use Test::Routine::Util;
with ('t::lib::Factory::Ledger');

use Moonpig::Context::Test -all, '$Context';

has ledger => (
  is   => 'rw',
  does => 'Moonpig::Role::Ledger',
  default => sub { $_[0]->test_ledger() },
  lazy => 1,
  clearer => 'scrub_ledger',
  handles => [ qw(accountant) ],
);

sub make_hold {
  my ($self) = @_;
  my ($b, $c) = $self->add_bank_and_consumer_to($self->ledger);
  my $h = $self->ledger->create_transfer({
    type => 'hold', from => $b, to => $c, amount => 1
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
  my ($b, $c) = $self->add_bank_and_consumer_to($self->ledger);
  my $t = $self->ledger->create_transfer({
    type => "transfer",
    from => $b,
    to   => $c,
    amount => 1,
  });

  dies_ok { $self->accountant->
              _convert_transfer_type($t, 'transfer' => 'hold') };

  my $h = $self->ledger->create_transfer({
    type => "hold",
    from => $b,
    to   => $c,
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

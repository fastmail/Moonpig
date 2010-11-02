package Moonpig::Transfer;
use Moose;

use Moonpig::Types qw(Millicents);

use namespace::autoclean;

my %BY_BANK;
my %BY_CONSUMER;

has bank => (
  is   => 'ro',
  does => 'Moonpig::Role::Bank',
  required => 1,
);

has consumer => (
  is   => 'ro',
  does => 'Moonpig::Role::Consumer',
  required => 1,
);

has amount => (
  is  => 'ro',
  isa =>  Millicents,
  coerce   => 1,
  required => 1,
);

sub _assert_no_overdraft {
  my ($self) = @_;

  confess "refusing to transfer funds beyond bank balance"
    if $self->bank->remaining_amount  -  $self->amount < 0;
}

sub BUILD {
  my ($self) = @_;

  $self->_assert_no_overdraft;

  my $bank_id = $self->bank->guid;
  $BY_BANK{ $bank_id } ||= [];
  push @{ $BY_BANK{ $bank_id } }, $self;

  my $consumer_id = $self->consumer->guid;
  $BY_CONSUMER{ $consumer_id } ||= [];
  push @{ $BY_CONSUMER{ $consumer_id } }, $self;
}

sub transfers_for_bank {
  my ($class, $bank) = @_;

  my $bank_id = $bank->guid;
  my $ref = $BY_BANK{ $bank_id } || [];
  return [ @$ref ];
}

sub transfers_for_consumer {
  my ($class, $consumer) = @_;

  my $consumer_id = $consumer->guid;
  my $ref = $BY_CONSUMER{ $consumer_id } || [];
  return [ @$ref ];
}

1;

package Moonpig::PaymentApplication;
use Moose;

use Moonpig::Types qw(Millicents);

use namespace::autoclean;

my %BY_PAYMENT;
my %BY_PAYABLE;

has payment => (
  is   => 'ro',
  does => 'Moonpig::Role::Payment',
  required => 1,
);

has payable => (
  is   => 'ro',
  does => 'Moonpig::Role::Payable',
  required => 1,
);

has amount => (
  is  => 'ro',
  isa =>  Millicents,
  coerce   => 1,
  required => 1,
);

sub _assert_no_overpayment {
  my ($self) = @_;

  confess "refusing to apply payment beyond remaining funds"
    if $self->payment->unapplied_amount  -  $self->amount < 0;
}

sub BUILD {
  my ($self) = @_;

  $self->_assert_no_overpayment;

  my $payment_id = $self->payment->guid;
  $BY_PAYMENT{ $payment_id } ||= [];
  push @{ $BY_PAYMENT{ $payment_id } }, $self;

  my $payable_id = $self->payable->guid;
  $BY_PAYABLE{ $payable_id } ||= [];
  push @{ $BY_PAYABLE{ $payable_id } }, $self;
}

sub applications_for_payment {
  my ($class, $payment) = @_;

  my $payment_id = $payment->guid;
  my $ref = $BY_PAYMENT{ $payment_id } || [];
  return [ @$ref ];
}

sub applications_for_payable {
  my ($class, $payable) = @_;

  my $payable_id = $payable->guid;
  my $ref = $BY_PAYABLE{ $payable_id } || [];
  return [ @$ref ];
}

1;

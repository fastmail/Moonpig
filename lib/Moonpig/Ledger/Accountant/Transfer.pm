package Moonpig::Ledger::Accountant::Transfer;
use Carp qw(confess croak);
use Moose;
use MooseX::StrictConstructor;
use Moonpig;
use Moonpig::Types qw(PositiveMillicents Time TransferType);
use Moonpig::TransferUtil qw(is_transfer_capable transfer_type_ok valid_type);

#
# This module is for internal use by Moonpig::Ledger::Accountant
# Please do not use it elsewhere.  20110202 mjd
#

with ('Moonpig::Role::HasGuid');

has source => (
  is => 'ro',
  isa => 'Moonpig::Role::HasGuid',
  required => 1,
);

has target => (
  is => 'ro',
  isa => 'Moonpig::Role::HasGuid',
  required => 1,
);

has type => (
  is => 'ro',
  isa => TransferType,
  required => 1,
);

has amount => (
  is => 'ro',
  isa => PositiveMillicents,
  required => 1,
);

has date => (
  is => 'ro',
  isa => Time,
  required => 1,
  default => sub { Moonpig->env->now() },
);

has ledger => (
  is => 'ro',
  isa => 'Moonpig::Role::Ledger',
  required => 1,
  handles => [ qw(accountant) ],
);

sub BUILD {
  my ($class, $arg) = @_;

  croak "Source cannot participate in transfers"
    unless $arg->{source}->does('Moonpig::Role::CanTransfer');
  my $s_type = $arg->{source}->transferer_type;

  croak "Target cannot participate in transfers"
    unless $arg->{source}->does('Moonpig::Role::CanTransfer');
  my $t_type = $arg->{target}->transferer_type;

  my $x_type = $arg->{type};
  croak "Unknown transfer type '$x_type'"
    unless valid_type($x_type);
  croak "Can't create transfer of type '$x_type' from $s_type to $t_type"
    unless transfer_type_ok($s_type, $t_type, $x_type);
}

sub is_deletable {
  my ($self) = @_;
  Moonpig::TransferUtil::deletable($self->type);
}

sub delete {
  my ($self) = @_;
  croak "Transfer of type " . $self->type . " is immortal"
    unless $self->is_deletable;
  $self->accountant->delete_transfer($self);
}

no Moose;
1;

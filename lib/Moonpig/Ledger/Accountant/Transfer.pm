package Moonpig::Ledger::Accountant::Transfer;
use Carp qw(confess croak);
use Moose;
use Moonpig;
use Moonpig::Types qw(PositiveMillicents Time TransferType);

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

  my $s_type = $arg->{source}->type;
  croak "Unknown transfer source type '$s_type'"
    unless Moonpig::TransferUtil->valid_type($s_type);

  my $t_type = $arg->{target}->type;
  croak "Unknown transfer target type '$t_type'"
    unless Moonpig::TransferUtil->valid_type($t_type);

  my $x_type = $arg->{type};
  croak "Can't create transfer of type '$x_type' from $s_type to $t_type"
    unless Moonpig::TransferUtil->transfer_type_ok($s_type, $t_type, $x_type);
}

sub is_deletable {
  my ($self) = @_;
  Moonpig::TransferUtil->deletable($self->type);
}

sub delete {
  my ($self) = @_;
  croak "Can't delete transfer of type " . $self->type
    unless $self->is_deletable;
  $self->accountant->delete_transfer($self);
}

no Moose;
1;

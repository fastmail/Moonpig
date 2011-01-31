package Moonpig::Role::CanTransfer;
# ABSTRACT: something that money can be transferred from / to
use MooseX::Role::Parameterized;
use Moonpig;
use Moonpig::Types qw(TransferCapable);

use namespace::autoclean;
parameter transfer_type_id => (isa => TransferCapable, required => 1);

role {
  my ($p) = @_;
  my $tti = $p->transfer_type_id;

  method transferer_type => sub { $tti };
};

1;

package Moonpig::Role::CanTransfer;
# ABSTRACT: something that money can be transferred from / to
use MooseX::Role::Parameterized 0.23;
use Moonpig;
use Moonpig::Types qw(TransferCapable);

use namespace::autoclean;
parameter transferer_type => (isa => TransferCapable, required => 1);

role {
  my ($p) = @_;
  my $tti = $p->transferer_type;

  method transferer_type => sub { $tti };

  method unapplied_amount => sub {
    my ($self) = @_;

    my $xfers_in  = $self->ledger->accountant->select({ target => $self });
    my $xfers_out = $self->ledger->accountant->select({ source => $self });
    return $xfers_in->total - $xfers_out->total;
  }
};

1;

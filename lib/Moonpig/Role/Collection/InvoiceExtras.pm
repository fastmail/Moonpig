package Moonpig::Role::Collection::InvoiceExtras;
use Moose::Role;
# ABSTRACT: extra behavior for a ledger's Invoice collection

use MooseX::Types::Moose qw(Str HashRef);
use Stick::Publisher 0.20110324;
use Stick::Publisher::Publish 0.20110504;

publish quotes => {} => sub {
  my ($self) = @_;
  return $self->filter(sub { $_->is_quote });
};

publish payable => {} => sub {
  my ($self) = @_;
  return $self->filter(sub { $_->is_payable });
};

1;

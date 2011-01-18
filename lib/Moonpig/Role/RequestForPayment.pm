package Moonpig::Role::RequestForPayment;
# ABSTRACT: something that performs dunning of invoices
use Moose::Role;

use Moonpig::Types qw(Invoice Time);
use MooseX::Types::Moose qw(ArrayRef);

with(
  'Moonpig::Role::StubBuild',
);

use namespace::autoclean;

has sent_at => (
  is       => 'ro',
  init_arg => undef,
  isa      => Time,
  default  => sub { Moonpig->env->now },
);

has invoices => (
  isa      => ArrayRef[ Invoice ],
  required => 1,
  traits   => [ 'Array' ],
  handles  => {
    invoices => 'elements',
    invoice_count => 'count',
  },
);

after BUILD => sub {
  my ($self) = @_;
  confess "can't send a RequestForPayment with 0 invoices"
    unless $self->invoice_count > 0;
};

1;

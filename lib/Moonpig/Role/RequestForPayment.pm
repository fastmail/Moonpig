package Moonpig::Role::RequestForPayment;
# ABSTRACT: something that performs dunning of invoices
use Moose::Role;

use Moonpig::Types qw(Invoice Time);
use MooseX::Types::Moose qw(ArrayRef);

with(
  'Moonpig::Role::StubBuild',
  'Moonpig::Role::HasGuid',
  'Stick::Role::PublicResource::GetSelf',
  'Moonpig::Role::HasCollections' => {
    item => 'invoice',
    item_roles => [ 'Moonpig::Role::Invoice' ],
    is => 'ro',
   },
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

sub invoice_array { [ $_[0]->invoices ] }

sub latest_invoice {
  my ($self) = @_;
  my $latest = (
    sort { $b->created_at <=> $a->created_at
        || $b->guid       cmp $a->guid # incredibly unlikely, but let's plan
         } $self->invoices
  )[0];

  return $latest;
}

after BUILD => sub {
  my ($self) = @_;
  confess "can't send a RequestForPayment with 0 invoices"
    unless $self->invoice_count > 0;
};

sub _subroute {
  my ($self, $path) = @_;
  my $path1 = shift @$path;
  return unless $path1 eq "invoices";
  return $self->invoice_collection;
}

sub STICK_PACK {
  my ($self) = @_;

  return {
    guid   => $self->guid,
    sent_at => $self->sent_at,
    invoices => [ map $_->guid, $self->invoices ],
  };
}


1;

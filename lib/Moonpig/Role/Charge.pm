package Moonpig::Role::Charge;
# ABSTRACT: a charge on an invoice or a journal
use Moose::Role;

use MooseX::Types::Moose qw(Str);
use Moonpig;
use Moonpig::Types qw(Millicents TagSet);

use Moonpig::Behavior::Packable;

use namespace::autoclean;

requires 'counts_toward_total';
requires 'check_amount';

with ('Moonpig::Role::HasTagset' => {});

has description => (
  is  => 'ro',
  isa => Str,
  required => 1,
);

has amount => (
  is  => 'ro',
  isa => Millicents,
  coerce   => 1,
  required => 1,
  trigger => sub {
    my ($self, $newval) = @_;
    $self->check_amount($newval);
  },
);

has date => (
  is      => 'ro',
  isa     => 'DateTime',
  default  => sub { Moonpig->env->now() },
);

PARTIAL_PACK {
  my ($self) = @_;

  return {
    description => $self->description,
    amount      => $self->amount,
    date        => $self->date,
    tags        => [ $self->taglist ],
  };
};

1;

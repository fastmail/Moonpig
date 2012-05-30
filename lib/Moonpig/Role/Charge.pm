package Moonpig::Role::Charge;
# ABSTRACT: a charge on an invoice or a journal
use Moose::Role;

use MooseX::Types::Moose qw(Str);
use Moonpig;
use Moonpig::Types qw(PositiveMillicents TagSet);

use Moonpig::Behavior::Packable;

use namespace::autoclean;

requires 'counts_toward_total';

with ('Moonpig::Role::HasTagset' => {});

has description => (
  is  => 'ro',
  isa => Str,
  required => 1,
);

has amount => (
  is  => 'ro',
  isa => PositiveMillicents,
  coerce   => 1,
  required => 1,
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

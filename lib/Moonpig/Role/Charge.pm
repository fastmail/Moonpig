package Moonpig::Role::Charge;
# ABSTRACT: a charge in a charge tree
use Moose::Role;

use MooseX::Types::Moose qw(Str);
use Moonpig;
use Moonpig::Types qw(PositiveMillicents TagSet);

use namespace::autoclean;

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

has tags => (
  isa => TagSet,
  default => sub {  []  },
  traits  => [ 'Array' ],
  handles => {
    tags => 'elements',
  },
);

sub STICK_PACK {
  my ($self) = @_;

  return {
    description => $self->description,
    amount      => $self->amount,
    date        => $self->date,
    tags        => $self->tags,
  }
}


1;

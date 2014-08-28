package Moonpig::App::Ob::Config;
# ABSTRACT: the Moonpig object browser configuration

use Moose;

use Moonpig;
use Moose::Util::TypeConstraints qw(role_type);

sub env {
  Moonpig->env;
}

sub storage {
  $_[0]->env->storage
}

has _dump_options => (
  isa => 'HashRef',
  is => 'ro',
  default => sub { {} },
  traits => [ 'Hash' ],
  handles => {
    set     => 'set',
    get     => 'get',
    dump_options   => 'elements',
  },
);

has maxlines => (
  isa => 'Num',
  is => 'rw',
  default => 10,
);

1;

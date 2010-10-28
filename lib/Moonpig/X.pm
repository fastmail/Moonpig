package Moonpig::X;
use Moose;

with(
  'Throwable',
  'Moonpig::Role::Happening',
);

has is_public => (
  is  => 'ro',
  isa => 'Bool',
  init_arg => 'public',
  default  => 0,
);

use namespace::clean -except => 'meta';

use overload '""' => sub { $_[0]->dump }, fallback => 1;
1;

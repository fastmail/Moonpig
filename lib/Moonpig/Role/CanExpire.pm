package Moonpig::Role::CanExpire;
# ABSTRACT: something that can expire
use Moose::Role;

use namespace::autoclean;

has is_expired => (
  is  => 'ro',
  isa => 'Bool',
  default => 0,
  traits  => [ 'Bool' ],
  handles => {
    'expire' => 'set',
  },
);

1;

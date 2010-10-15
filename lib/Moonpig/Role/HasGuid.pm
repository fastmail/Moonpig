package Moonpig::Role::HasGuid;
use Moose::Role;

use Data::GUID qw(guid);
use Moose::Util::TypeConstraints;

use namespace::autoclean;

has guid_object => (
  is  => 'ro',
  isa => class_type('Data::GUID'),
  init_arg => undef,
  default  => sub { guid() },
  handles  => { guid => 'as_string' },
);

1;

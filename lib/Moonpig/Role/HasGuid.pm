package Moonpig::Role::HasGuid;
# ABSTRACT: something with a GUID (nearly everything)
use Moose::Role;

use Data::GUID qw(guid_string);
use Moose::Util::TypeConstraints;

use namespace::autoclean;

has guid => (
  is  => 'ro',
  isa => 'Str', # refine this -- rjbs, 2010-12-02
  init_arg => undef,
  default  => sub { guid_string },
);

1;

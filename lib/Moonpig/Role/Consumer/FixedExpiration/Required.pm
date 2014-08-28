package Moonpig::Role::Consumer::FixedExpiration::Required;
# ABSTRACT: a consumer that expires automatically on a particular date

use Moose::Role;

use MooseX::Types::Moose qw(Str);
use Moonpig::Types qw(PositiveMillicents Time);

with(
  'Moonpig::Role::Consumer::FixedExpiration',
);

sub expiration_date;
has expiration_date => (
  is  => 'ro',
  isa => Time,
  required => 1,
);

1;

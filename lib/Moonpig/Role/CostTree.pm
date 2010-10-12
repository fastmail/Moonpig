package Moonpig::Role::CostTree;
use Moose::Role;

use Moose::Util::TypeConstraints;
use MooseX::Types::Moose qw(ArrayRef HashRef);

use namespace::autoclean;

has _subtree_for => (
  is  => 'ro',
  isa => HashRef[ role_type('Moonpig::Role::CostTree') ],
  default => sub {  {}  },
);

has charges => (
  is  => 'ro',
  isa => ArrayRef[ role_type('Moonpig::Role::Charge') ],
);

1;

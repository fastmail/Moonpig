package Moonpig::Role::CostTree;
use Moose::Role;

use Moose::Util::TypeConstraints;
use MooseX::Types::Moose qw(ArrayRef HashRef);

use namespace::autoclean;

has _subtree_for => (
  is  => 'ro',
  isa => HashRef[ role_type('Moonpig::Role::CostTree') ],
  default => sub {  {}  },
  traits  => [ 'Hash' ],
  handles => {
    has_subtree_for  => 'exists',
    subtree_for      => 'get',
    _set_subtree_for => 'set',
  },
);

has _parent => (
  is   => 'ro',
  does => 'Moonpig::Role::CostTree',
  predicate => '_has_parent',
);

sub find_or_create_subtree_for {
  my ($self, $path) = @_;

  if (@$path == 1) {
    my $name = $path->[0];
    return $self->subtree_for($name) if $self->has_subtree_for($name);

    my $subtree = $self->meta->name->new({
      _parent => $self,
    });

    $self->_set_subtree_for($name, $subtree);
  }

  my ($head, @rest) = @$path;
  return $self->find_or_create_subtree_for($head)
              ->find_or_create_subtree_for(\@rest);
}

has charges => (
  is  => 'ro',
  isa => ArrayRef[ role_type('Moonpig::Role::Charge') ],
);

sub subtrees {
  my ($self) = shift;
  values %{$self->_subtree_for()};
}

1;

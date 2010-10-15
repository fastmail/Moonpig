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
    subtrees         => 'values',
  },
);

has _parent => (
  is   => 'ro',
  does => 'Moonpig::Role::CostTree',
  predicate => '_has_parent',
);

#
# Legal options:
#  create - if true, create the specified path if it does not exist

sub find_or_create_path {
  my ($self, $path) = @_;
  $self->path_search($path, { create => 1 });
}

sub path_search {
  my ($self, $path, $opt) = @_;
  my $create = $opt->{create};

  if (@$path == 1) {
    my $name = $path->[0];
    return $self->subtree_for($name) if $self->has_subtree_for($name);
    return unless $create;

    my $subtree = $self->meta->name->new({
      _parent => $self,
    });

    $self->_set_subtree_for($name, $subtree);
    return $subtree;
  }

  my ($head, @rest) = @$path;
  my $next = $self->path_search($head, $opt) or return;
  return     $next->path_search(\@rest, $opt);
}

has charges => (
  is  => 'ro',
  isa => ArrayRef[ role_type('Moonpig::Role::Charge') ],
);

1;

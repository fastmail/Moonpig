package Moonpig::Role::CostTree;
use Moose::Role;

use DateTime;
use List::MoreUtils qw(any);
use List::Util qw(max);
use Moonpig::Util qw(same_object);
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

# Root of the cost tree that this cost is in
sub root {
  my $this = shift;
  $this = $this->_parent while $this->_has_parent;
  return $this;
}

# Use this when adding a subtree to ensure that there are no loops
# in the cost tree graph.
sub _contains_cost_tree {
  my ($self, $cost_tree, $seen) = @_;
  return 0 if $seen->{$self}++;

  return 1 if same_object($self, $cost_tree);
  if (any { same_object($_, $cost_tree)
              || $_->_contains_cost_tree($cost_tree, $seen) }
      $self->subtrees) {
    return 1;
  } else {
    return 0;
  }
}

# This is the date of the latest item in the cost tree
has last_date => (
  is   => 'rw',
  isa  => 'DateTime',
  lazy => 1,
  default => sub { $_[0]->_compute_last_date },
);

# This method recalculates the last date for the target object
# and its ancestors.
sub _compute_last_date {
  my ($self) = @_;
  my $last = max(0, map $_->date, $self->charges);
  $last = max($last, map $_->last_date, $self->subtrees);
  # if it changed, propagate the change to the parent
  $self->_update_last_date($last);
  return $last;
}

# A new charge with the specified date has been added somewhere below this
# cost tree; update this object's ->last_date if necessary.
# You must consider calling this whenever you add a charge or a
# subtree to a cost tree.
sub _update_last_date {
  my ($self, $date) = @_;
  if (_date_after($date, $self->last_date())) {
    $self->last_date($date);
    $self->_parent->_update_last_date($date) if $self->_has_parent;
  }
}

sub _date_after { DateTime->compare(@_[0,1]) > 1 }

sub find_or_create_path {
  my ($self, $path) = @_;
  $self->path_search($path, { create => 1 });
}

#
# Legal options:
#   create - if true, create the specified path if it does not exist
# To add later:
#   replace - if supplied, replace target subtree with this one
sub path_search {
  my ($self, $path, $opt) = @_;
  my $create = $opt->{create};

  if (@$path == 0) { return $self }
  elsif (@$path == 1) {
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
  my $next = $self->path_search([$head], $opt) or return;
  return     $next->path_search(\@rest, $opt);
}

has _charges => (
  is  => 'ro',
  isa => ArrayRef[ role_type('Moonpig::Role::Charge') ],
  default => sub { [] },
  traits  => [ 'Array' ],
  handles => {
    charges  => 'elements',
    n_charges => 'count',
    _push_charge => 'push',
  },
);

sub add_charge {
  my ($self, $charge) = @_;
  $self->_push_charge($charge);
  $self->_update_last_date($charge->date);
}

1;

package Moonpig::Role::ChargeTree;
# ABSTRACT: a hierarchy of charges
use Moose::Role;

use DateTime;
use DateTime::Infinite;
use List::MoreUtils qw(any);
use List::Util qw(first max);
use Moonpig::Util qw(same_object);
use Moonpig::Types qw(ChargePath ChargePathPart);
use Moose::Util::TypeConstraints;
use MooseX::Types::Moose qw(ArrayRef HashRef);

use namespace::autoclean;

my $LONG_AGO = DateTime::Infinite::Past->new;

has _subtree_for => (
  is  => 'ro',
  isa => HashRef[ role_type('Moonpig::Role::ChargeTree') ],
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
  does => 'Moonpig::Role::ChargeTree',
  predicate => '_has_parent',
);

# Root of the cost tree that this cost is in
sub root {
  my $this = shift;
  $this = $this->_parent while $this->_has_parent;
  return $this;
}

sub _leaf_name {
  my ($self) = @_;
  my @names;

  my $this = $self;
  while ($this->_has_parent and $this = $this->_parent) {
    my $subtree_hash = $this->_subtree_for;
    my $name = first { same_object($self, $subtree_hash->{ $_ }) }
               keys %$subtree_hash;

    confess "can't find subtree in parent" unless defined $name;

    push @names, $name;
  }

  return join '.', reverse @names;
}

# Use this when adding a subtree to ensure that there are no loops
# in the cost tree graph.
sub _contains_charge_tree {
  my ($self, $charge_tree, $seen) = @_;
  return 0 if $seen->{$self}++;

  return 1 if same_object($self, $charge_tree);
  if (any { same_object($_, $charge_tree)
              || $_->_contains_charge_tree($charge_tree, $seen) }
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
  default => sub { $LONG_AGO },
);

# This method recalculates the last date for the target object
# and its ancestors.
sub _compute_last_date {
  my ($self) = @_;
  my $last = _date_max($LONG_AGO, map $_->date, $self->charges);
  $last = _date_max($last, map $_->last_date, $self->subtrees);
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
sub _date_max {
  my ($max, @d) = @_;
  $max = _date_after($_, $max) ? $_ : $max for @d;
  return $max;
}

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
  my ($self, $path, $arg) = @_;

  $path = ChargePath->assert_coerce($path);
  $self->_trusted_path_search($path, $arg);
}

sub _trusted_path_search {
  my ($self, $path, $arg) = @_;
  my $create = $arg->{create};

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
  my $next = $self->_trusted_path_search([$head], $arg) or return;
  return     $next->_trusted_path_search(\@rest, $arg);
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

sub add_charge_at {
  my ($self, $charge, $path) = @_;

  $self->find_or_create_path($path)->add_charge($charge);
}

sub total_amount {
  my ($self) = @_;

  my $amount = 0;
  $amount += $_->amount for $self->charges;
  $amount += $_->total_amount for $self->subtrees;

  return $amount;
}

sub apply_to_all_charges {
  my ($self, $code) = @_;

  $code->() for $self->charges;
  for my $tree ($self->subtrees) {
    $tree->apply_to_all_charges( $code );
  }
}

1;

package Moonpig::CostTree::Basic;
use Moose;

use Moonpig::Util qw(same_object);
use List::MoreUtils qw(any);

with 'Moonpig::Role::CostTree';

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


1;

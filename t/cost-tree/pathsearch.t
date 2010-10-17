use strict;
use warnings;

use Test::More;

use Moonpig::CostTree::Basic;

use Moonpig::Util -all;

my @ct;
push @ct, Moonpig::CostTree::Basic->new() for 0..5;

note q{   a    b              };
note q{ 0 -> 1 -> 2           };
note q{      \ c              };
note q{       `-> 3 -> 4 -> 5 };
note q{             d    f    };

$ct[0]->_set_subtree_for(a => $ct[1]);
$ct[1]->_set_subtree_for(b => $ct[2]);
$ct[1]->_set_subtree_for(c => $ct[3]);
$ct[3]->_set_subtree_for(d => $ct[4]);
$ct[4]->_set_subtree_for(f => $ct[5]);

# Good paths
for my $test ([ [], 0 ],
              [ ["a"], 1 ],
              [ ["a", "b"], 2],
              [ ["a", "c"], 3],
              [ ["a", "c", "d"], 4],
              [ ["a", "c", "d", "f"], 5],
             ) {
  my ($path, $expected) = @$test;
  my $p = join "/", @$path;
  is($ct[0]->path_search($path), $ct[$expected], "0 -> $p -> $expected");
}

my @old = @ct;
# Bad paths
for my $path (["b"], ["a", "a"], ["a", "d"], ["a", "x", "y", "z"]) {
  my $p = join "/", @$path;
  is($ct[0]->path_search($path), undef(), "0 -> $p -> nowhere");
  my $new = $ct[0]->path_search($path, { create => 1 });
  ok($new, "created $p");
  $new == $_ and die for @old;  # WHAAAA?
  is($ct[0]->path_search($path), $new, "0 -> $p -> new");
  push @old, $new;

  my @parent_path = @$path;
  pop @parent_path;
  is($new->_parent, $ct[0]->path_search(\@parent_path), "parent(new) ok");
}



done_testing;

use strict;
use warnings;

use Test::More;

use Moonpig::CostTree::Basic;

use Moonpig::Util -all;

my @ct;
push @ct, Moonpig::CostTree::Basic->new() for 0..5;

note q{                 ,--.  };
note q{ 0 -> 1 -> 2    /    \ };
note q{ ^    \         v    | };
note q{ |     `-> 3 -> 4 -> 5 };
note q{ \         |           };
note q{  `--------'           };

$ct[0]->_set_subtree_for(a => $ct[1]);
$ct[1]->_set_subtree_for(b => $ct[2]);
$ct[1]->_set_subtree_for(c => $ct[3]);
$ct[3]->_set_subtree_for(d => $ct[4]);
$ct[3]->_set_subtree_for(e => $ct[0]);
$ct[4]->_set_subtree_for(f => $ct[5]);
$ct[5]->_set_subtree_for(g => $ct[4]);

# xy here means that we expect tree x to contain tree y
# otherwise we expect it won't.
my %contains = map { $_ => 1 }
  qw(00 01 02 03 04 05
     10 11 12 13 14 15
           22
     30 31 32 33 34 35
                 44 45
                 54 55
   );

for my $x (0..5) {
  for my $y (0..5) {
    is($ct[$x]->_contains_cost_tree($ct[$y]), $contains{"$x$y"} || 0,
       "$x contains $y? ");
  }
}

done_testing;





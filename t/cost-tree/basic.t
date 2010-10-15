use strict;
use warnings;

use Test::More;

use Moonpig::CostTree::Basic;

use Moonpig::Util -all;

my $ct0 = Moonpig::CostTree::Basic->new();
my $ct1 = Moonpig::CostTree::Basic->new(_subtree_for => { zero => $ct0 });


{ my @st = $ct0->subtrees;
  is(@st, 0);
}

{ my @st = $ct1->subtrees;
  is(@st, 1);
  is($st[0], $ct0);
  is($ct1->_subtree_for->{"zero"}, $ct0);
}

done_testing;

use strict;
use warnings;

use Test::More;

use Moonpig::Util -all;

my $ct0 = class('ChargeTree')->new();
my $ct1 = class('ChargeTree')->new(_subtree_for => { zero => $ct0 });


{ my @st = $ct0->subtrees;
  is(@st, 0);
}

{ my @st = $ct1->subtrees;
  is(@st, 1);
  is($st[0], $ct0);
  is($ct1->_subtree_for->{"zero"}, $ct0);
}

done_testing;

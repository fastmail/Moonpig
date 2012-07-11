package t::lib::Role::TestLineItem;
use Moonpig;

use Moose::Role;
with ('Moonpig::Role::LineItem');

sub line_item_type { "test" }

1;

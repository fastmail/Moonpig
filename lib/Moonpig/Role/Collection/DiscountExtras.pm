package Moonpig::Role::Collection::DiscountExtras;
# ABSTRACT: extra behavior for a ledger's Discount collection

use Moose::Role;

use Moonpig::Util qw(class event);
use Stick::Publisher 0.20110324;
use Stick::Publisher::Publish 0.20110504;

sub add { ... }

1;


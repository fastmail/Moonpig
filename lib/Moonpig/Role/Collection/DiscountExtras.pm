package Moonpig::Role::Collection::DiscountExtras;
use Moose::Role;
# ABSTRACT: extra behavior for a ledger's Discount collection

use Moonpig::Util qw(class event);
use Stick::Publisher 0.20110324;
use Stick::Publisher::Publish 0.20110504;

sub add { ... }

1;


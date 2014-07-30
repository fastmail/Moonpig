package Moonpig::Role::Consumer::ChargeOnDemand;
# ABSTRACT: a consumer that issues charges only on explicit instructions

use Moose::Role;
use namespace::autoclean;

# We only charge if someone calls ->charge_current_journal, or the like. --
# rjbs, 2014-07-30
sub charge {}

1;

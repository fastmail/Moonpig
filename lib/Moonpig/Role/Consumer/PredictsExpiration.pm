package Moonpig::Role::Consumer::PredictsExpiration;
use Moose::Role;

use namespace::autoclean;

requires 'estimated_lifetime'; # TimeInterval, from created to predicted exp
requires 'expiration_date';    # Time, predicted exp date
requires 'remaining_life';     # TimeInterval, from now to predicted exp

1;

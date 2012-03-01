package Moonpig::Role::Consumer::PredictsExpiration;
use Moose::Role;

use namespace::autoclean;

requires 'estimated_lifetime';
requires 'expiration_date';
requires 'remaining_life';

1;

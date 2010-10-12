package Moonpig::Types;
use MooseX::Types -declare => [ qw(Millicents) ];

use MooseX::Types::Moose qw(Int Num);

use namespace::autoclean;

subtype Millicents, as Int;

coerce Millicents, from Num, via { int };

1;

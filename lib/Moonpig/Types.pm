package Moonpig::Types;
use MooseX::Types -declare => [ qw(EmailAddresses Millicents) ];

use MooseX::Types::Moose qw(ArrayRef Int Num);
use Email::Address;

use namespace::autoclean;

subtype Millicents, as Int;

coerce Millicents, from Num, via { int };

subtype EmailAddresses, as ArrayRef, where {
  @$_ > 0
  and
  @$_ == grep { /\@/ } @$_
};

1;

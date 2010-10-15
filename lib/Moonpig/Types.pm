package Moonpig::Types;
use MooseX::Types -declare => [ qw(EmailAddresses Ledger Millicents) ];

use MooseX::Types::Moose qw(ArrayRef Int Num);
use Email::Address;

use namespace::autoclean;

subtype EmailAddresses, as ArrayRef, where {
  @$_ > 0
  and
  @$_ == grep { /\@/ } @$_
};

role_type Ledger, { role => 'Moonpig::Role::Ledger' };

subtype Millicents, as Int;

coerce Millicents, from Num, via { int };

1;

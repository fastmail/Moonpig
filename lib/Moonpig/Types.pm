package Moonpig::Types;
use MooseX::Types -declare => [ qw(
  EmailAddresses
  Ledger Millicents

  CostPath CostPathPart CostPathStr
) ];

use MooseX::Types::Moose qw(ArrayRef Int Num Str);
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

my $path_part_re = qr/[-a-z0-9]+/i;

subtype CostPathPart, as Str, where { $_ =~ /\A$path_part_re\z/ };
subtype CostPath, as ArrayRef[ CostPathPart ];

subtype CostPathStr,
  as Str,
  where { /\A (?: $path_part_re \. )* $path_part_re \z/x };

coerce CostPath, from CostPathStr, via { [ split /\./, $_ ] };

1;

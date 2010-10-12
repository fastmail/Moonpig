package Moonpig::Types;
use MooseX::Types -declare => [ qw(MoneyAmount _BigFloat) ];

use Math::BigFloat;
use MooseX::Types::Moose qw(Num);

use namespace::autoclean;

class_type _BigFloat, { class => 'Math::BigFloat' };
subtype MoneyAmount, as _BigFloat, where { $_->precision == -4 };

coerce MoneyAmount,
  from _BigFloat,
  via { my $amt = $_->copy; $amt->precision(-4); $amt };

coerce MoneyAmount,
  from Num,
  via { my $amt = Math::BigFloat->new($_); $amt->precision(-4); $amt };

1;

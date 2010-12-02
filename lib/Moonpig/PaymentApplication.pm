package Moonpig::PaymentApplication;
use Moose;

use Moonpig::Types qw(Millicents);

use namespace::autoclean;

use Moose::Util::TypeConstraints;

with(
  'Moonpig::Role::TransferLike' => {
    from_name => 'payment',
    from_type => role_type('Moonpig::Role::Payment'),

    to_name   => 'payable',
    to_type   => role_type('Moonpig::Role::Payable'),
  },
);

1;

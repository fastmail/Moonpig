package Moonpig::CreditApplication;
# ABSTRACT: the application of a credit to a payable
use Moose;

use Moonpig::Types qw(Millicents);

use namespace::autoclean;

use Moose::Util::TypeConstraints;

with(
  'Moonpig::Role::TransferLike' => {
    from_name => 'credit',
    from_type => role_type('Moonpig::Role::Credit'),

    to_name   => 'payable',
    to_type   => role_type('Moonpig::Role::Payable'),
  },
);

1;

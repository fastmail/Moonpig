package Moonpig::Transfer;
# ABSTRACT: a transfer of money from a bank to a consumer
use Moose;

use Moonpig::Types qw(Millicents);

use Moose::Util::TypeConstraints;

use namespace::autoclean;

with(
  'Moonpig::Role::TransferLike' => {
    from_name => 'bank',
    from_type => role_type('Moonpig::Role::Bank'),

    to_name   => 'consumer',
    to_type   => role_type('Moonpig::Role::Consumer'),
  },
);

1;

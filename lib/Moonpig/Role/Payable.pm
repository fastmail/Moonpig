package Moonpig::Role::Payable;
# ABSTRACT: something to which credits may be applied
use Moose::Role;

with(
  'Moonpig::Role::CanTransfer' => { transfer_type_id => "payable" },
);

1;

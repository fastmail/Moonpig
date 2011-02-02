package Moonpig::Role::Payable;
# ABSTRACT: something to which credits may be applied
use Moose::Role;

with(
  'Moonpig::Role::CanTransfer' => { transferer_type => "payable" },
);

1;

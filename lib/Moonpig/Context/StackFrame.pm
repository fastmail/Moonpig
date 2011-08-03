package Moonpig::Context::StackFrame;
use Moose;
extends 'Global::Context::StackFrame::Basic';

use namespace::autoclean;

has memoranda => (
  isa => 'ArrayRef',
  init_arg => undef,
  traits   => [ 'Array' ],
  default  => sub {  []  },
  handles  => {
    add_memorandum => 'push',
  },
);

1;

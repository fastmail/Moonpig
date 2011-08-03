package Moonpig::Context;
use parent 'Global::Context';

use Moonpig::Context::StackFrame;

sub common_globref { \*Object }

sub default_frame_class   { 'Moonpig::Context::StackFrame' }

1;

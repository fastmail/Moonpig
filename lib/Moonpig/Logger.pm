use strict;
use warnings;
package Moonpig::Logger;
use base 'Log::Dispatchouli::Global';

sub logger_globref {
  no warnings 'once';
  \*Logger;
}

1;

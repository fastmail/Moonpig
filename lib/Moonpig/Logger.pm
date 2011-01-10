use strict;
use warnings;
package Moonpig::Logger;
# ABSTRACT: the global Log::Dispatchouli logger for Moonpig
use base 'Log::Dispatchouli::Global';

sub logger_globref {
  no warnings 'once';
  \*Logger;
}

1;

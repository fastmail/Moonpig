use strict;
use warnings;
package Moonpig::Logger;
# ABSTRACT: the global Log::Dispatchouli logger for Moonpig

use parent 'Log::Dispatchouli::Global';

use Log::Dispatchouli 2.002 (); # env_prefix

sub logger_globref {
  no warnings 'once';
  \*Logger;
}

sub default_logger_class { 'Moonpig::Logger::_Logger' }

{
  package
    Moonpig::Logger::_Logger;
  use parent 'Log::Dispatchouli';

  sub env_prefix { 'MOONPIG' }
}

1;

use strict;
package Moonpig::Context::Test;
use Moonpig::Context -all, '$Context';

BEGIN { our @ISA = qw(Moonpig::Context) };

require Global::Context::Terminal::Basic;
ctx_init({
  terminal => Global::Context::Terminal::Basic->new({ uri => 'x' }),
});

1;

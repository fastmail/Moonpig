use strict;
use warnings;

package t::lib::TestEnv;

use Test::File::ShareDir 0.003001 -share => {
  -dist => { 'Moonpig' => 'share' }
};

use Moonpig::Env::Test;

use Moonpig::Context::Test '$Context';

1;

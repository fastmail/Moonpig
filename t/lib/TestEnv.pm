use strict;
use warnings;

package t::lib::TestEnv;

use Moonpig::Logger::Test;

use Test::File::ShareDir 0.003001 -share => {
  -dist => { 'Moonpig' => 'share' }
};

use Moonpig::Env::Test;

$ENV{MOONPIG_TESTING} = 1;

1;

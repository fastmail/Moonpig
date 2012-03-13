use strict;
use warnings;

use Test::More;
use Test::Fatal;

{
  my $err = exception {
    require Moonpig;
    Moonpig->import;
    Moonpig->env;
  };

  like(
    "$err",
    qr/not yet configured/,
    "an environment must be configured before it is accessed",
  );
}

{
  my $err = exception {
    require Moonpig::Env::Test;
    Moonpig::Env::Test->import;
    require t::lib::Env::Bogus;
    t::lib::Env::Bogus->import;
  };

  like(
    "$err",
    qr/environment is already configured/,
    "can't load two environments",
  );
}

done_testing;


use strict;
use warnings;

use Test::More;
use Test::Fatal;

{
  my $err = exception {
    require Moonpig;
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
    require Moonpig::Env::Normal;
  };

  like(
    "$err",
    qr/environment is already configured/,
    "can't load two environments",
  );
}

done_testing;


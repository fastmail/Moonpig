use strict;
use lib 'lib';

use Moonpig::Web::App;
use Moonpig::Env::Test;

my $guid = do {
  package Test;
  use Moose;
  with 't::lib::Factory::Ledger';

  my $ledger = __PACKAGE__->test_ledger;
  $ledger->guid;
};

warn "CREATED LEDGER $guid\n";

return Moonpig::Web::App->app;

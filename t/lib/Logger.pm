use strict;
use warnings;
package t::lib::Logger;
use base 'Moonpig::Logger';

use Moonpig::Logger '$Logger' => { init => {
  ident     => "moonpig-test($0)",
  to_self   => 1,
  to_stdout => $ENV{MOONPIG_LOG_STDERR},
  facility  => undef,
  log_pid   => 0,
} };

if ($ENV{MOONPIG_DIAG}) {
  require Log::Dispatch::Null;
  my $diagger = Log::Dispatch::Null->new(
    min_level => 'debug',
  );
  $diagger->add_callback( sub {
    my %p = @_;
    Test::More::diag($p{message});
  });

  $Logger->dispatcher->add($diagger);
}

1;

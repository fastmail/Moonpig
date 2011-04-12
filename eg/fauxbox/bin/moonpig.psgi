#!perl
use strict;
use warnings;

use lib 'lib';
use lib 'eg/fauxbox/lib';

use Log::Dispatch::Null;
use Term::ANSIColor;

use Moonpig::Logger '$Logger' => { init => {
  ident     => "fauxbox-moonpig($0)",
  log_pid   => 0,
} };

# I tried to use a Handle logger to go through the color filter program, but
# there were stderr/stdout issues.  Whatever, this is simpler.
# -- rjbs, 2011-03-30
my $null = Log::Dispatch::Null->new(min_level => 'debug');
$null->add_callback(sub {
  warn color('magenta') . {@_}->{message} . color('reset') . "\n";
});
$Logger->dispatcher->add($null);

my $root = $ENV{MOONPIG_STORAGE_ROOT} = 'eg/fauxbox/db';

mkdir $root unless -d $root;

use Moonpig::Web::App;
use Fauxbox::Moonpig::Env;

use Fauxbox::Moonpig::TemplateSet;

Moonpig->env->storage->_ensure_tables_exist;

return Moonpig::Web::App->app;

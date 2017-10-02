#!perl
use strict;
use warnings;

use lib 'lib';
use lib 'eg/fauxbox/lib';

$ENV{MOONPIG_TESTING} = 1;

use Log::Dispatch::Null;
use Term::ANSIColor;

use Test::File::ShareDir -share => { -dist   => { 'Moonpig' => 'share' } };

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

for (map {; "$_\_STORAGE_ROOT" } qw(MOONPIG FAUXBOX)) {
  $ENV{$_} = 'eg/fauxbox/var' unless exists $ENV{$_};
}
my $root = $ENV{MOONPIG_STORAGE_ROOT};

-d $root or mkdir $root or die "mkdir $root: $!";

use Moonpig::Web::App;
use Fauxbox::Moonpig::Env;

use Fauxbox::Moonpig::TemplateSet;

Moonpig->env->storage->_ensure_tables_exist;

return Moonpig::Web::App->app;

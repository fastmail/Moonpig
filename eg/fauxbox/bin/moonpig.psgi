use strict;
use warnings;

use lib 'lib';
use lib 'eg/fauxbox/lib';

my $root = $ENV{MOONPIG_STORAGE_ROOT} = 'eg/fauxbox/db';

mkdir $root unless -d $root;

use Moonpig::Web::App;
use Moonpig::Env::Test;

use Fauxbox::Moonpig::TemplateSet;

return Moonpig::Web::App->app;

use strict;
use warnings;

use lib 'lib';
use lib 'eg/unalay/lib';

my $root = $ENV{MOONPIG_STORAGE_ROOT} = 'eg/unalay/db';

mkdir $root unless -d $root;

use Moonpig::Web::App;
use Moonpig::Env::Test;

use Unalay::Moonpig::TemplateSet;

return Moonpig::Web::App->app;

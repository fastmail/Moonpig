
use Test::More;

BEGIN { use_ok('Moonpig::App::Ob') }

my $ob = Moonpig::App::Ob->new();
ok($ob);

done_testing;
